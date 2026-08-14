//! Shared tooling modules — Rust ports of the Python scripts in `scripts/`.
//!
//! These modules replace the Python tooling (`scripts/*.py`, `tools/*.py`)
//! with native Rust implementations. Each submodule corresponds to a group
//! of Python scripts:
//!
//! - [`common`] — shared utilities (DuckDB connection, CSV normalization,
//!   T-SQL translation, value formatting, energy model, gold comparison,
//!   op splitting)
//! - [`gen`] — GROUP A: SQL generation (`generate_ops.py`, `gen_remaining_ops.py`,
//!   `gen_spatial_ops.py`, `split_ops.py`)
//! - [`verify`] — GROUP D: verification (`verify_ops.py`, `verify_all_variants.py`,
//!   `capture_gold.py`, `capture_gold_v2.py`, `test_current_state.py`)
//! - [`search`] — GROUP B: search/optimization (`search_harness.py`,
//!   `search_harness_wave6.py`)
//! - [`build`] — GROUP C: export/build (`export_mssql_*.py`, `build_duckdb*.py`,
//!   `build_schema_variants.py`)
//! - [`fixes`] — GROUP E: fixes/patches (`fix_ops.py`, `fix_op41_sensitive_data.py`,
//!   `apply_op41_fix_to_variants.py`)

pub mod common;
pub mod gen;
pub mod verify;
pub mod search;
pub mod build;
pub mod fixes;
pub mod tooling;
