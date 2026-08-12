//! DataMigrata — Energy-Optimal MSSQL-to-DuckDB Migration Compiler
//!
//! Rust-native implementation. Translates MSSQL T-SQL operations to DuckDB SQL,
//! minimizing energy consumption through schema optimization and query rewrites.
//!
//! # Pipeline
//!
//! 1. [`parser`] — MSSQL T-SQL → AST using `sqlparser-rs` (MSSQL dialect)
//! 2. [`ir`] — AST → DataFusion `LogicalPlan` (engine-agnostic relational algebra IR)
//! 3. [`optimizer`] — `LogicalPlan` → optimized `LogicalPlan` (energy-aware rewrite rules)
//! 4. [`codemodel`] — optimized `LogicalPlan` → DuckDB SQL string
//! 5. [`catalog`] — Logical MSSQL schema → physical DuckDB schema mapping (multiple variants)
//!
//! # Design Principles
//!
//! - **Energy-first**: every transformation is evaluated for joule impact
//! - **Deterministic**: all transformations are pure functions
//! - **Complete IR**: DataFusion LogicalPlan captures all T-SQL semantics
//! - **Multiple physical alternatives**: at least 3 rewrite strategies per feature gap
//! - **Correctness gate**: output validated against MSSQL gold-standard result sets

pub mod parser;
pub mod ir;
pub mod optimizer;
pub mod codemodel;
pub mod catalog;

pub use parser::{MssqlDialect, ParseError, ParseResult, MssqlParser};
pub use ir::{IrError, IrResult, AstToLogicalPlan};
pub use optimizer::{OptimizationEngine, OptimizationResult, RuleApplied};
pub use codemodel::{DuckdbGenerator, CodeGenerationResult, PipelineResult, PipelineIntegration};
pub use catalog::{Catalog, CatalogEntry, SchemaVariant};

/// Run the full pipeline on a single MSSQL T-SQL statement.
///
/// Returns the generated DuckDB SQL string on success.
pub fn run_pipeline(tsql: &str) -> Result<PipelineResult, PipelineError> {
    PipelineIntegration::new().run(tsql)
}

/// Top-level pipeline error — wraps all phase-specific errors.
#[derive(thiserror::Error, Debug)]
pub enum PipelineError {
    #[error("parse error: {0}")]
    Parse(#[from] ParseError),

    #[error("IR lowering error: {0}")]
    Ir(#[from] IrError),

    #[error("optimization error: {0}")]
    Optimization(#[from] optimizer::OptimizationError),

    #[error("code generation error: {0}")]
    Codegen(#[from] codemodel::CodegenError),

    #[error("catalog error: {0}")]
    Catalog(#[from] catalog::CatalogError),
}
