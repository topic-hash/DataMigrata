//! Build DuckDB database from schema.json (v2).
//!
//! Direct port of `scripts/build_duckdb_v2.py`.
//!
//! Uses `schema.json` to generate DDL dynamically instead of hardcoded.

use std::path::Path;

use super::build_duckdb::{ALL_TABLES, csv_filename};
use super::super::common::duckdb_conn::{execute, open_read_write};

/// Fix type: VARCHAR(-1) → VARCHAR.
fn fix_type(t: &str) -> String {
    t.replace("VARCHAR(-1)", "VARCHAR")
}

/// Build the DuckDB database from schema.json and CSV files.
///
/// Direct port of the top-level script in `build_duckdb_v2.py`.
pub fn build(db_path: &Path, schema_json: &Path, data_dir: &Path) -> anyhow::Result<()> {
    if db_path.exists() {
        let bak = db_path.with_extension("duckdb.bak");
        let _ = std::fs::copy(db_path, &bak);
    }

    let con = open_read_write(db_path)?;

    // Load schema.json
    let schema_content = std::fs::read_to_string(schema_json)?;
    let schema: serde_json::Value = serde_json::from_str(&schema_content)?;

    // Create schemas
    for schema_name in &["HR", "Sales", "Archive", "Audit", "Security", "Staging"] {
        let _ = execute(&con, &format!("CREATE SCHEMA IF NOT EXISTS {}", schema_name));
    }

    // Build tables from schema.json
    if let Some(obj) = schema.as_object() {
        for table_name in ALL_TABLES {
            if let Some(cols) = obj.get(*table_name).and_then(|v| v.as_array()) {
                let mut col_defs = Vec::new();
                for col in cols {
                    if let Some(arr) = col.as_array() {
                        if arr.len() >= 3 {
                            let col_name = arr[0].as_str().unwrap_or("");
                            let duck_type = arr[2].as_str().unwrap_or("VARCHAR");
                            let fixed = fix_type(duck_type);
                            col_defs.push(format!("\"{}\" {}", col_name, fixed));
                        }
                    }
                }
                let ddl = format!("CREATE TABLE {} ({})", table_name, col_defs.join(", "));
                let _ = execute(&con, &format!("DROP TABLE IF EXISTS {}", table_name));
                execute(&con, &ddl)?;

                if let Some(csv) = csv_filename(table_name) {
                    let csv_path = data_dir.join(csv);
                    let copy_sql = format!(
                        "COPY {} FROM '{}' (HEADER false, DELIM ',', QUOTE '\"', ESCAPE '\"', NULL '', FORMAT CSV, IGNORE_ERRORS 1000)",
                        table_name,
                        csv_path.display()
                    );
                    let _ = execute(&con, &copy_sql);
                }

                let count: i64 = con
                    .query_row(&format!("SELECT COUNT(*) FROM {}", table_name), [], |r| r.get(0))
                    .unwrap_or(0);
                eprintln!("  {}: {} rows", table_name, count);
            }
        }
    }

    Ok(())
}
