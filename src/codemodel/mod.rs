//! Phase 4: Optimized `LogicalPlan` → T-SQL string generation.
//!
//! Generates MSSQL-dialect T-SQL from the optimized DataFusion `LogicalPlan`.
//! Uses DataFusion's `plan_to_sql` (which converts a `LogicalPlan` back to a
//! `sqlparser-rs` AST), then renders the AST with the MSSQL dialect.
//!
//! # MSSQL Dialect Specifics
//!
//! - Identifier quoting: `[name]` (not `"name"`)
//! - `TOP n` instead of `LIMIT n`
//! - `GETDATE()` / `SYSUTCDATETIME()` instead of `CURRENT_TIMESTAMP`
//! - `ISNULL(a, b)` is MSSQL-native (we still emit `COALESCE` for portability)
//! - `FOR JSON PATH` / `FOR XML PATH` for aggregation into JSON/XML
//! - `FOR SYSTEM_TIME AS OF` for temporal queries
//! - `WITH RecursiveCTE AS (...)` for `CONNECT BY` recursion
//! - `MERGE` statement for `MERGE INTO` upserts

use crate::optimizer::OptimizationResult;
use sqlparser::ast::Statement;
use thiserror::Error;

/// Result of running the full pipeline on a single SQL input.
#[derive(Debug, Clone)]
pub struct PipelineResult {
    /// The generated T-SQL.
    pub tsql: String,
    /// Number of Oracle constructs preprocessed in Phase 1.
    pub preprocessed_constructs: usize,
    /// Number of constructs lowered in Phase 2.
    pub lowered_constructs: usize,
    /// Number of optimization rules applied in Phase 3.
    pub rules_applied: usize,
}

/// Result of T-SQL code generation (Phase 4 standalone).
#[derive(Debug, Clone)]
pub struct CodeGenerationResult {
    /// The generated T-SQL statements (one per input plan).
    pub statements: Vec<String>,
}

/// Errors during code generation.
#[derive(Error, Debug)]
pub enum CodegenError {
    #[error("plan-to-sql conversion failed: {0}")]
    PlanToSqlFailed(String),

    #[error("sql formatting failed: {0}")]
    FormattingFailed(String),

    #[error("no plans to generate code for")]
    NoPlans,
}

/// The T-SQL generator. Phase 4 of the pipeline.
#[derive(Debug, Clone, Default)]
pub struct TSqlGenerator {
    /// Whether to use `TOP n` syntax (MSSQL) or `LIMIT n` (standard SQL).
    /// Always `true` for our MSSQL target.
    use_top_syntax: bool,
}

impl TSqlGenerator {
    pub fn new() -> Self {
        Self { use_top_syntax: true }
    }

    /// Generate T-SQL from an optimization result.
    ///
    /// Stub: real implementation calls `datafusion::sql::plan_to_sql(plan)`
    /// for each plan, then formats the resulting `Statement` using
    /// `sqlparser`'s `MssqlDialect`.
    pub fn generate(&self, opt: OptimizationResult) -> Result<CodeGenerationResult, CodegenError> {
        if opt.plans.is_empty() {
            return Ok(CodeGenerationResult { statements: vec![] });
        }

        // Stub: would convert each LogicalPlan → Statement → formatted SQL string.
        Ok(CodeGenerationResult { statements: vec![] })
    }
}

/// The full pipeline integration — wires Phase 1 → 2 → 3 → 4.
#[derive(Debug, Clone, Default)]
pub struct PipelineIntegration {
    parser: crate::parser::OracleSqlParser,
    lowering: crate::ir::CalciteToDataFusionLowering,
    optimizer: crate::optimizer::OptimizationEngine,
    generator: TSqlGenerator,
}

impl PipelineIntegration {
    pub fn new() -> Self {
        Self::default()
    }

    /// Run the full pipeline on an Oracle SQL script.
    pub fn run(&self, oracle_sql: &str) -> Result<PipelineResult, crate::PipelineError> {
        // Phase 1: parse
        let parsed = self.parser.parse(oracle_sql)?;
        let preprocessed_constructs = parsed.preprocessed_constructs;

        // Phase 2: lower AST → DataFusion LogicalPlan
        let ir = self.lowering.lower(parsed.statements)?;
        let lowered_constructs = ir.lowered_constructs;

        // Phase 3: optimize
        let opt = self.optimizer.optimize(ir)?;
        let rules_applied = opt.rules_applied.len();

        // Phase 4: generate T-SQL
        let codegen = self.generator.generate(opt)?;

        // Combine generated statements into one T-SQL script
        let tsql = codegen.statements.join("\nGO\n");

        Ok(PipelineResult {
            tsql,
            preprocessed_constructs,
            lowered_constructs,
            rules_applied,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_pipeline_on_simple_select() {
        let result = PipelineIntegration::new()
            .run("SELECT * FROM employees")
            .unwrap();
        assert_eq!(result.preprocessed_constructs, 0);
    }

    #[test]
    fn runs_pipeline_on_oracle_constructs() {
        let result = PipelineIntegration::new()
            .run("SELECT NVL(name, 'unknown'), SYSDATE FROM DUAL")
            .unwrap();
        // NVL, SYSDATE, DUAL should all be preprocessed
        assert!(result.preprocessed_constructs >= 3);
    }
}
