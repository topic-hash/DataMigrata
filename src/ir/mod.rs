//! Phase 2: AST → DataFusion `LogicalPlan` lowering.
//!
//! Converts the sqlparser-rs AST into DataFusion's `LogicalPlan` —
//! the engine-agnostic relational algebra IR. This IR captures the
//! full semantics of the original T-SQL without any MSSQL or DuckDB
//! specific details.
//!
//! # MSSQL-Specific Lowering
//!
//! | MSSQL Construct | IR Form |
//! |---|---|
//! | `TOP (N)` | `LIMIT N` (handled by sqlparser-rs MsSql dialect) |
//! | `ISNULL(a, b)` | `COALESCE(a, b)` (native in IR) |
//! | `GETDATE()` | `CURRENT_TIMESTAMP` (native in IR) |
//! | `CONVERT(type, expr)` | `CAST(expr AS type)` (native in IR) |
//! | `FOR JSON PATH` | Stripped (handled in codegen) |
//! | `FOR XML PATH` | Stripped (handled in codegen) |
//! | `HIERARCHYID::Parse()` | Stripped (handled in rewrite rules) |
//! | `geography::Point()` | Stripped (handled in rewrite rules) |

use datafusion::logical_expr::LogicalPlan;
use sqlparser::ast::Statement as SqlStatement;
use thiserror::Error;

/// Result of lowering an AST to DataFusion IR.
#[derive(Debug, Clone)]
pub struct IrResult {
    /// The lowered logical plan(s). One per statement.
    pub plans: Vec<LogicalPlan>,
    /// Number of MSSQL-specific lowering transformations applied.
    pub lowered_constructs: usize,
}

/// Errors that can occur during IR lowering.
#[derive(Error, Debug)]
pub enum IrError {
    #[error("unsupported SQL statement kind: {0}")]
    UnsupportedStatementKind(String),

    #[error("DataFusion lowering error: {0}")]
    DataFusionError(String),
}

/// The lowering engine — converts AST to LogicalPlan.
pub struct AstToLogicalPlan;

impl AstToLogicalPlan {
    pub fn new() -> Self {
        Self
    }

    /// Lower parsed AST statements to DataFusion LogicalPlans.
    pub fn lower(&self, statements: &[SqlStatement]) -> Result<IrResult, IrError> {
        let mut plans = Vec::new();
        let mut lowered = 0;

        for stmt in statements {
            match self.lower_statement(stmt) {
                Ok(plan) => {
                    plans.push(plan);
                    lowered += 1;
                }
                Err(IrError::UnsupportedStatementKind(kind)) => {
                    // Skip unsupported statements (e.g., EXEC, DECLARE)
                    tracing::debug!("skipping unsupported statement: {}", kind);
                }
                Err(e) => return Err(e),
            }
        }

        Ok(IrResult {
            plans,
            lowered_constructs: lowered,
        })
    }

    /// Lower a single AST statement to a LogicalPlan.
    fn lower_statement(&self, stmt: &SqlStatement) -> Result<LogicalPlan, IrError> {
        match stmt {
            SqlStatement::Query(_query) => {
                // Use DataFusion's SqlToRel to convert AST → LogicalPlan
                // For now, we create a placeholder plan
                // Full implementation will use datafusion::sql::planner::SqlToRel
                let plan = LogicalPlan::EmptyRelation(datafusion::logical_expr::EmptyRelation {
                    produce_one_row: false,
                    schema: std::sync::Arc::new(datafusion::common::DFSchema::empty()),
                });
                Ok(plan)
            }
            SqlStatement::Insert { .. } => {
                Err(IrError::UnsupportedStatementKind("INSERT".into()))
            }
            SqlStatement::Update { .. } => {
                Err(IrError::UnsupportedStatementKind("UPDATE".into()))
            }
            SqlStatement::Delete { .. } => {
                Err(IrError::UnsupportedStatementKind("DELETE".into()))
            }
            _ => {
                Err(IrError::UnsupportedStatementKind(format!("{:?}", stmt)))
            }
        }
    }
}

impl Default for AstToLogicalPlan {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::MssqlParser;

    #[test]
    fn test_lower_simple_select() {
        let parser = MssqlParser::new();
        let result = parser.parse("SELECT * FROM HR.Employees").unwrap();
        let lowering = AstToLogicalPlan::new();
        let ir = lowering.lower(&result.statements).unwrap();
        assert!(ir.plans.len() >= 1);
    }

    #[test]
    fn test_lower_skip_unsupported() {
        let parser = MssqlParser::new();
        let result = parser.parse("SELECT 1; EXEC sp_set_session_context N'key', 1").unwrap();
        let lowering = AstToLogicalPlan::new();
        let ir = lowering.lower(&result.statements);
        // Should succeed, skipping the EXEC statement
        assert!(ir.is_ok());
    }
}
