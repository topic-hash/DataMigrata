//! Export MSSQL tables to CSV via pyodbc (v1).
//!
//! Direct port of `scripts/export_mssql_pyodbc.py`.
//!
//! NOTE: This module requires ODBC connectivity. In the Rust port, we
//! delegate to `export_mssql_data` (Docker/sqlcmd-based) which produces
//! equivalent output without requiring an ODBC driver.

use std::path::Path;

use super::export_mssql_data::export_all;

/// Export all tables and views via sqlcmd (replaces pyodbc).
pub fn export(out_dir: &Path) -> anyhow::Result<()> {
    export_all(out_dir)
}
