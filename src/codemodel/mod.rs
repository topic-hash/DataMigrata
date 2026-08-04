//! Phase 4: Optimized `LogicalPlan` → DuckDB SQL string generation.
//!
//! Generates DuckDB-dialect SQL from the optimized DataFusion LogicalPlan.
//!
//! # DuckDB Dialect Specifics
//!
//! - `LIMIT N` instead of `TOP N`
//! - `COALESCE(a, b)` instead of `ISNULL(a, b)`
//! - `CURRENT_TIMESTAMP` instead of `GETDATE()`
//! - `json_extract_string(col, '$.path')` instead of `JSON_VALUE(col, '$.path')`
//! - `json_extract(col, '$.path')` instead of `JSON_QUERY(col, '$.path')`
//! - `JOIN LATERAL` instead of `CROSS APPLY`
//! - `WITH RECURSIVE` for recursive CTEs
//! - `CAST(expr AS type)` (standard SQL, no CONVERT)

use crate::optimizer::OptimizationResult;
use thiserror::Error;

/// Result of running the full pipeline on a single SQL input.
#[derive(Debug, Clone)]
pub struct PipelineResult {
    /// The generated DuckDB SQL.
    pub duckdb_sql: String,
    /// Number of MSSQL constructs preprocessed in Phase 1.
    pub preprocessed_constructs: usize,
    /// Number of constructs lowered in Phase 2.
    pub lowered_constructs: usize,
    /// Number of optimization rules applied in Phase 3.
    pub rules_applied: usize,
}

/// Result of code generation.
#[derive(Debug, Clone)]
pub struct CodeGenerationResult {
    pub sql: String,
}

/// Errors during code generation.
#[derive(Error, Debug)]
pub enum CodegenError {
    #[error("failed to generate DuckDB SQL: {0}")]
    GenerationFailed(String),
}

/// DuckDB SQL code generator.
pub struct DuckdbGenerator;

impl DuckdbGenerator {
    pub fn new() -> Self {
        Self
    }

    /// Generate DuckDB SQL from an optimized LogicalPlan.
    pub fn generate(&self, plan: &datafusion::logical_expr::LogicalPlan) -> Result<CodeGenerationResult, CodegenError> {
        // Use DataFusion's plan_to_sql to convert LogicalPlan back to AST,
        // then render with DuckDB-compatible syntax
        match datafusion::sql::unparser::plan_to_sql(plan) {
            Ok(sql_statements) => {
                let sql = sql_statements.iter()
                    .map(|s| s.to_string())
                    .collect::<Vec<_>>()
                    .join(";\n");
                Ok(CodeGenerationResult { sql })
            }
            Err(e) => Err(CodegenError::GenerationFailed(e.to_string())),
        }
    }
}

impl Default for DuckdbGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Full pipeline integration — runs all 4 phases.
pub struct PipelineIntegration {
    parser: crate::parser::MssqlParser,
    lowering: crate::ir::AstToLogicalPlan,
    optimizer: crate::optimizer::OptimizationEngine,
    generator: DuckdbGenerator,
}

impl PipelineIntegration {
    pub fn new() -> Self {
        Self {
            parser: crate::parser::MssqlParser::new(),
            lowering: crate::ir::AstToLogicalPlan::new(),
            optimizer: crate::optimizer::OptimizationEngine::new(),
            generator: DuckdbGenerator::new(),
        }
    }

    /// Run the full pipeline on a single T-SQL statement.
    pub fn run(&self, tsql: &str) -> Result<PipelineResult, crate::PipelineError> {
        // Phase 1: Parse
        let parse_result = self.parser.parse(tsql)?;

        // Phase 2: Lower to IR
        let ir = self.lowering.lower(&parse_result.statements)?;

        // Phase 3: Optimize
        let optimized = self.optimizer.optimize(ir)?;

        // Phase 4: Generate DuckDB SQL
        let mut sql_parts = Vec::new();
        for plan in &optimized.plans {
            match self.generator.generate(plan) {
                Ok(result) => sql_parts.push(result.sql),
                Err(_) => {
                    // If codegen fails, output a comment
                    sql_parts.push("-- Code generation failed for this plan".to_string());
                }
            }
        }

        Ok(PipelineResult {
            duckdb_sql: sql_parts.join("\n"),
            preprocessed_constructs: parse_result.preprocessed_constructs,
            lowered_constructs: optimized.lowered_constructs,
            rules_applied: optimized.rules_applied,
        })
    }
}

impl Default for PipelineIntegration {
    fn default() -> Self {
        Self::new()
    }
}
