//! DuckDB connection helper.
//!
//! Wraps the `duckdb` crate with convenience methods used across the
//! ported scripts.

use std::path::Path;

use duckdb::{AccessMode, Config, Connection};

/// Open a read-only DuckDB connection.
pub fn open_read_only(db_path: &Path) -> Result<Connection, duckdb::Error> {
    let config = Config::default().access_mode(AccessMode::ReadOnly)?;
    Connection::open_with_flags(db_path, config)
}

/// Open a read-write DuckDB connection.
pub fn open_read_write(db_path: &Path) -> Result<Connection, duckdb::Error> {
    let config = Config::default().access_mode(AccessMode::ReadWrite)?;
    Connection::open_with_flags(db_path, config)
}

/// Execute a SQL statement, returning the number of affected rows.
pub fn execute(con: &Connection, sql: &str) -> Result<usize, duckdb::Error> {
    con.execute(sql, []).map(|n| n as usize)
}

/// Execute multiple semicolon-separated statements.
///
/// Returns `Ok(())` if all succeed, or the first error.
pub fn execute_batch(con: &Connection, sql: &str) -> Result<(), duckdb::Error> {
    con.execute_batch(sql)
}

/// Run a query and return all rows as `Vec<Vec<duckdb::types::Value>>`.
pub fn query_rows(
    con: &Connection,
    sql: &str,
) -> Result<Vec<Vec<duckdb::types::Value>>, duckdb::Error> {
    let mut stmt = con.prepare(sql)?;
    let rows = stmt.query_map([], |row| {
        let mut values = Vec::new();
        let col_count = row.as_ref().column_count();
        for i in 0..col_count {
            let val: duckdb::types::Value = row.get(i)?;
            values.push(val);
        }
        Ok(values)
    })?;
    let mut result = Vec::new();
    for row in rows {
        result.push(row?);
    }
    Ok(result)
}
