//! Export MSSQL tables to CSV (v2 — datetime2 as VARCHAR, RLS toggle).
//!
//! Direct port of `scripts/export_mssql_v2.py`.
//!
//! NOTE: This module requires ODBC connectivity. In the Rust port, we
//! delegate to `export_mssql_data` (Docker/sqlcmd-based) which produces
//! equivalent output without requiring an ODBC driver.

use std::path::Path;

use super::export_mssql_data::export_all;

/// Export all tables and views via sqlcmd (replaces pyodbc v2).
pub fn export(out_dir: &Path) -> anyhow::Result<()> {
    export_all(out_dir)
}
