//! DataMigrata — Intelligent Oracle-to-MSSQL Semantic Translation Middleware
//!
//! Rust-native implementation. No Java. No TypeScript. No GC pauses.
//!
//! # Pipeline
//!
//! 1. [`parser`] — Oracle SQL → AST using `sqlparser-rs` (with Oracle dialect extensions)
//! 2. [`ir`] — AST → DataFusion `LogicalPlan` (Rust-native IR, replaces Calcite RelNode)
//! 3. [`optimizer`] — `LogicalPlan` → optimized `LogicalPlan` (rule-based + cost-based)
//! 4. [`codemodel`] — optimized `LogicalPlan` → T-SQL string (MSSQL dialect)
//! 5. [`protocol`] — TNS server (incoming, Oracle clients) + TDS client (outgoing, MSSQL)
//!
//! # Design Principles
//!
//! - **Zero-copy parsing** wherever feasible (`winnow` for binary TNS, `sqlparser-rs` for SQL text)
//! - **No GC pauses** — Rust ownership model eliminates GC-induced tail latency spikes
//! - **Memory safety without runtime cost** — safe Rust eliminates ~70% of memory safety CVEs
//!   without the runtime overhead of RC<RefCell> or GC
//! - **Async-first** — `tokio` for concurrent connection handling, proven at RisingWave scale
//!   (~200K lines of Rust, 5-10x lower memory than equivalent Java systems)

pub mod parser;
pub mod ir;
pub mod optimizer;
pub mod codemodel;
pub mod protocol;

pub use parser::{OracleDialect, ParseError, ParseResult, OracleSqlParser};
pub use ir::{IrError, IrResult, CalciteToDataFusionLowering};
pub use optimizer::{OptimizationEngine, OptimizationResult, RuleApplied};
pub use codemodel::{TSqlGenerator, CodeGenerationResult, PipelineResult, PipelineIntegration};

/// Run the full 4-phase pipeline on a single Oracle SQL statement.
///
/// Returns the generated T-SQL string on success.
pub fn run_pipeline(oracle_sql: &str) -> Result<PipelineResult, PipelineError> {
    PipelineIntegration::new().run(oracle_sql)
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
}
