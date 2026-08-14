//! Shared utilities used across all ported Python scripts.
//!
//! Each submodule is a direct Rust port of the corresponding Python function:
//!
//! - [`sql_translate`] — `translate_tsql_to_duckdb()`, `split_statements()`
//! - [`value_fmt`] — `fmt_value()`, `rows_to_csv()`, `_normalize_dt_str()`
//! - [`csv_norm`] — `normalize_csv_text()`, `md5_of_text()`
//! - [`energy`] — energy model (`cpu_joules`, `dram_joules`, `load_mssql_joules()`)
//! - [`gold`] — gold-standard comparison (`verify_op()` logic)
//! - [`op_splitter`] — regex-based op file splitting
//! - [`duckdb_conn`] — DuckDB connection helper

pub mod sql_translate;
pub mod value_fmt;
pub mod csv_norm;
pub mod energy;
pub mod gold;
pub mod op_splitter;
pub mod duckdb_conn;

/// Default project root — matches the Python scripts' `ROOT` constant.
///
/// The Python scripts hardcode `/home/z/my-project`. In Rust we default to
/// the same path but allow override via the `--root` CLI flag.
pub const DEFAULT_ROOT: &str = "/home/z/my-project";

/// Resolve a path relative to the project root.
pub fn root_path(root: &str, sub: &str) -> std::path::PathBuf {
    std::path::Path::new(root).join(sub)
}
