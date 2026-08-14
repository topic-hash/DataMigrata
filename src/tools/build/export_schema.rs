//! Generate DuckDB-compatible schema from MSSQL column types.
//!
//! Direct port of `scripts/export_schema.py`.
//!
//! Queries MSSQL column types and generates DuckDB-compatible schema
//! (JSON + DDL SQL). Uses the `TYPE_MAP` for MSSQL → DuckDB type mapping.

use std::path::Path;
use std::io::Write;

use super::export_mssql_data::TABLES;

/// MSSQL type → DuckDB type mapping.
///
/// Direct port of `TYPE_MAP` from `export_schema.py`.
pub fn mssql_to_duckdb(data_type: &str, precision: i32, scale: i32, max_length: i32) -> String {
    let dt = data_type.to_lowercase();
    match dt.as_str() {
        "int" => "INTEGER".into(),
        "bigint" => "BIGINT".into(),
        "smallint" => "SMALLINT".into(),
        "tinyint" => "UTINYINT".into(),
        "bit" => "INTEGER".into(),
        "decimal" | "numeric" => format!("DECIMAL({},{})", if precision > 0 { precision } else { 18 }, scale),
        "money" => "DECIMAL(19,4)".into(),
        "smallmoney" => "DECIMAL(10,4)".into(),
        "float" => "DOUBLE".into(),
        "real" => "FLOAT".into(),
        "datetime" | "datetime2" | "smalldatetime" => "TIMESTAMP".into(),
        "date" => "DATE".into(),
        "time" => "TIME".into(),
        "char" | "varchar" | "nchar" | "nvarchar" => {
            if max_length == -1 || max_length == 0 {
                "VARCHAR".into()
            } else {
                format!("VARCHAR({})", max_length)
            }
        }
        "text" | "ntext" => "VARCHAR".into(),
        "binary" | "varbinary" | "image" => "BLOB".into(),
        "uniqueidentifier" => "VARCHAR(36)".into(),
        "xml" | "geography" | "geometry" | "hierarchyid" => "VARCHAR".into(),
        "timestamp" => "BLOB".into(), // rowversion
        _ => "VARCHAR".into(),
    }
}

/// Generate schema.json and duckdb_schema.sql from MSSQL.
///
/// Direct port of `main()` from `export_schema.py`.
///
/// NOTE: This requires querying MSSQL via ODBC. In the Rust port, we
/// generate the schema from the hardcoded TABLES list and known column
/// types. For a full implementation, use `tiberius` or `odbc` crate.
pub fn generate_schema(out_dir: &Path) -> anyhow::Result<()> {
    std::fs::create_dir_all(out_dir)?;

    // Generate a minimal schema.json from the known table list
    // A full implementation would query INFORMATION_SCHEMA.COLUMNS via ODBC
    let mut json = serde_json::json!({});
    for (schema, table) in TABLES {
        let full_name = format!("{}.{}", schema, table);
        json[full_name] = serde_json::json!([]);
    }

    let schema_json_path = out_dir.join("schema.json");
    std::fs::write(&schema_json_path, serde_json::to_string_pretty(&json)?)?;

    // Generate minimal DDL
    let ddl_path = out_dir.join("duckdb_schema.sql");
    let mut f = std::fs::File::create(&ddl_path)?;
    for schema in &["HR", "Sales", "Archive", "Audit", "Security", "Staging"] {
        writeln!(f, "CREATE SCHEMA IF NOT EXISTS {};", schema)?;
    }

    eprintln!("Schema generated (minimal — use ODBC for full column types)");
    eprintln!("  {}", schema_json_path.display());
    eprintln!("  {}", ddl_path.display());

    Ok(())
}
