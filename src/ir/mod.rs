//! Phase 2: AST → DataFusion `LogicalPlan` lowering.
//!
//! Replaces the Java/Calcite `RelNode` tree with Rust-native DataFusion's
//! `LogicalPlan`. DataFusion is the Rust-native equivalent of Apache Calcite:
//!
//! - SQL frontend (uses `sqlparser-rs`)
//! - Logical plan representation (`LogicalPlan`, `Expr`, `Plan` types)
//! - Rule-based optimizer framework
//! - Physical plan generation
//!
//! # Why DataFusion (not Calcite)
//!
//! - No JVM, no GC pauses, no startup overhead
//! - Pure Rust — integrates natively with `tokio` async runtime
//! - Production-proven (DataFusion, InfluxDB IOx, Ballista, GlueSQL, RisingWave)
//! - Same conceptual model as Calcite (logical → physical plan separation)
//!
//! # Lowering Strategy
//!
//! Oracle-specific transformations applied during lowering:
//!
//! | Oracle Construct | DataFusion IR Form |
//! |------------------|-------------------|
//! | `DECODE(x, k1, v1, ...)` | `CASE x WHEN k1 THEN v1 ... END` |
//! | `NVL(a, b)` | `COALESCE(a, b)` |
//! | `SYSDATE` | `CURRENT_TIMESTAMP` |
//! | `SYSTIMESTAMP - INTERVAL 'n' DAY` | `date_add(interval, current_timestamp())` |
//! | `CONNECT BY` recursion | Recursive CTE (`LogicalPlan::With` + recursive scan) |
//! | `(+)=` outer join | `LEFT JOIN` / `RIGHT JOIN` (preprocessed in Phase 1) |
//! | `DUAL` table | Removed (no `LogicalPlan::TableScan` if no real table) |
//! | `ROWNUM` | `row_number() OVER ()` window function |

use datafusion::logical_expr::LogicalPlan;
use sqlparser::ast::Statement as SqlStatement;
use thiserror::Error;

/// Result of lowering an AST to DataFusion IR.
#[derive(Debug, Clone)]
pub struct IrResult {
    /// The lowered logical plan(s). One per statement.
    pub plans: Vec<LogicalPlan>,
    /// Number of Oracle-specific lowering transformations applied.
    pub lowered_constructs: usize,
}

/// Errors that can occur during IR lowering.
#[derive(Error, Debug)]
pub enum IrError {
    #[error("unsupported SQL statement kind: {0}")]
    UnsupportedStatementKind(String),

    #[error("lowering failed: {0}")]
    LoweringFailed(String),

    #[error("empty input — no statements to lower")]
    EmptyInput,
}

/// The IR lowering engine. Phase 2 of the pipeline.
#[derive(Debug, Clone, Default)]
pub struct CalciteToDataFusionLowering;

impl CalciteToDataFusionLowering {
    pub fn new() -> Self {
        Self
    }

    /// Lower a list of parsed AST statements into DataFusion logical plans.
    ///
    /// Note: this is a scaffolding stub. Full lowering uses DataFusion's
    /// `SqlToRel` translator (from `datafusion::sql`) to convert `sqlparser-rs`
    /// ASTs into `LogicalPlan` trees. Oracle-specific transformations are applied
    /// via a custom `SqlToRel`-wrapping visitor that rewrites Oracle AST nodes
    /// into DataFusion-compatible forms before translation.
    ///
    /// `preprocessed_constructs` is the count from Phase 1 — it tells us how
    /// many Oracle-specific constructs the parser already rewrote. We propagate
    /// this as `lowered_constructs` so the optimizer knows there is work to do.
    pub fn lower(&self, statements: Vec<SqlStatement>) -> Result<IrResult, IrError> {
        if statements.is_empty() {
            return Err(IrError::EmptyInput);
        }

        // Stub: real implementation calls `SqlToRel::sql_statement_to_plan`.
        // For now we count the supported constructs and return an empty plan list,
        // to be filled in when we wire up the actual DataFusion SQL planner.
        let mut lowered = 0;
        for stmt in &statements {
            if Self::has_oracle_construct(stmt) {
                lowered += 1;
            }
        }

        Ok(IrResult {
            plans: Vec::new(), // Filled in by real DataFusion SqlToRel wiring
            lowered_constructs: lowered,
        })
    }

    /// Lower with the parser's preprocessed-construct count as a hint.
    /// This is the entry point used by the pipeline integration.
    pub fn lower_with_count(
        &self,
        statements: Vec<SqlStatement>,
        preprocessed_constructs: usize,
    ) -> Result<IrResult, IrError> {
        if statements.is_empty() {
            return Err(IrError::EmptyInput);
        }

        // Use the max of (AST-detected constructs, parser-reported constructs)
        // so both paths contribute. The parser's count is authoritative for
        // constructs that were rewritten before AST construction (SYSDATE, NVL,
        // DUAL, XML functions, Flashback, etc.).
        let mut lowered = preprocessed_constructs;
        for stmt in &statements {
            if Self::has_oracle_construct(stmt) {
                lowered += 1;
            }
        }

        Ok(IrResult {
            plans: Vec::new(),
            lowered_constructs: lowered,
        })
    }

    /// Detect whether the statement contains Oracle-specific constructs that
    /// require lowering transformation.
    fn has_oracle_construct(_stmt: &SqlStatement) -> bool {
        // Stub: real impl walks the AST looking for DECODE/NVL/SYSDATE/etc.
        // For scaffolding purposes we return false — the test harness will
        // exercise this once the real visitor is implemented.
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::OracleSqlParser;

    #[test]
    fn lowers_simple_select() {
        let parsed = OracleSqlParser::new().parse("SELECT * FROM employees").unwrap();
        let result = CalciteToDataFusionLowering::new().lower(parsed.statements).unwrap();
        assert_eq!(result.lowered_constructs, 0);
    }

    #[test]
    fn rejects_empty_input() {
        let result = CalciteToDataFusionLowering::new().lower(Vec::new());
        assert!(matches!(result, Err(IrError::EmptyInput)));
    }
}
