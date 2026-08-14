//! GROUP C — Export/build scripts.
//!
//! Ports of:
//! - `scripts/export_mssql_data.py` → [`export_mssql_data`]
//! - `scripts/export_mssql_pyodbc.py` → [`export_mssql_pyodbc`]
//! - `scripts/export_mssql_v2.py` → [`export_mssql_v2`]
//! - `scripts/export_schema.py` → [`export_schema`]
//! - `scripts/build_duckdb.py` → [`build_duckdb`]
//! - `scripts/build_duckdb_v2.py` → [`build_duckdb_v2`]
//! - `scripts/build_duckdb_v3.py` → [`build_duckdb_v3`]
//! - `scripts/build_duckdb_views.py` → [`build_duckdb_views`]
//! - `scripts/build_duckdb_views_v2.py` → [`build_duckdb_views_v2`]
//! - `scripts/build_schema_variants.py` → [`build_schema_variants`]

pub mod export_mssql_data;
pub mod export_mssql_pyodbc;
pub mod export_mssql_v2;
pub mod export_schema;
pub mod build_duckdb;
pub mod build_duckdb_v2;
pub mod build_duckdb_v3;
pub mod build_duckdb_views;
pub mod build_duckdb_views_v2;
pub mod build_schema_variants;
