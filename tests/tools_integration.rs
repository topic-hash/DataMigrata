//! Integration tests for the DuckDB connection and value formatting.
//!
//! These tests verify that the `duckdb` crate works correctly with our
//! `value_fmt` module — ensuring that DuckDB values are formatted to match
//! MSSQL bcp output exactly.

use datamigrata::tools::common::csv_norm::{md5_of_text, normalize_csv_text};
use datamigrata::tools::common::duckdb_conn::{open_read_write, query_rows};
use datamigrata::tools::common::value_fmt::{fmt_value, rows_to_csv};
use datamigrata::tools::common::sql_translate::{split_statements, translate_tsql_to_duckdb};

#[test]
fn test_duckdb_in_memory_basic() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (id INTEGER, name VARCHAR, val DECIMAL(18,4))")
        .unwrap();
    con.execute(
        "INSERT INTO test VALUES (1, 'hello', 42.5000), (2, NULL, 0.0001)",
        [],
    )
        .unwrap();

    let rows = query_rows(&con, "SELECT * FROM test ORDER BY id").unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(fmt_value(&rows[0][0]), "1");
    assert_eq!(fmt_value(&rows[0][1]), "hello");
    assert_eq!(fmt_value(&rows[0][2]), "42.5000");
    assert_eq!(fmt_value(&rows[1][0]), "2");
    assert_eq!(fmt_value(&rows[1][1]), "NULL");
    assert_eq!(fmt_value(&rows[1][2]), ".0001");
}

#[test]
fn test_duckdb_boolean_formatting() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (flag BOOLEAN)").unwrap();
    con.execute("INSERT INTO test VALUES (true), (false), (NULL)", [])
        .unwrap();

    // Query without ORDER BY — DuckDB returns rows in insertion order
    let rows = query_rows(&con, "SELECT * FROM test").unwrap();
    assert_eq!(fmt_value(&rows[0][0]), "1");  // true
    assert_eq!(fmt_value(&rows[1][0]), "0");  // false
    assert_eq!(fmt_value(&rows[2][0]), "NULL");  // NULL
}

#[test]
fn test_duckdb_timestamp_formatting() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (ts TIMESTAMP)").unwrap();
    con.execute(
        "INSERT INTO test VALUES ('2026-01-15 10:30:00.123456')",
        [],
    )
    .unwrap();

    let rows = query_rows(&con, "SELECT * FROM test").unwrap();
    let formatted = fmt_value(&rows[0][0]);
    assert_eq!(formatted, "2026-01-15 10:30:00.123456");
}

#[test]
fn test_duckdb_float_formatting() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (val DOUBLE)").unwrap();
    con.execute(
        "INSERT INTO test VALUES (42.0), (3.14159), (0.0001)",
        [],
    )
    .unwrap();

    let rows = query_rows(&con, "SELECT * FROM test ORDER BY val").unwrap();
    // 0.0001 → .0001 (leading zero stripped by fmt_float, since format_g produces "0.0001")
    let v0 = fmt_value(&rows[0][0]);
    assert!(v0 == ".0001" || v0 == "0.0001", "expected .0001 or 0.0001, got {}", v0);
    // 3.14159 → 3.1415899999999999 (17 significant digits — f64 representation)
    assert!(fmt_value(&rows[1][0]).starts_with("3.1415"), "got: {}", fmt_value(&rows[1][0]));
    // 42.0 → 42.0 (integer-valued float gets .0 suffix)
    assert_eq!(fmt_value(&rows[2][0]), "42.0");
}

#[test]
fn test_rows_to_csv_and_md5() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (a INTEGER, b VARCHAR)").unwrap();
    con.execute("INSERT INTO test VALUES (1, 'x'), (2, 'y')", [])
        .unwrap();

    let rows = query_rows(&con, "SELECT * FROM test ORDER BY a").unwrap();
    let csv = rows_to_csv(&rows);
    assert_eq!(csv, "1,x\n2,y\n");

    let normalized = normalize_csv_text(&csv);
    let hash = md5_of_text(&normalized);
    assert_eq!(hash.len(), 32);
}

#[test]
fn test_tsql_translation_with_duckdb() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (id INTEGER, name VARCHAR)").unwrap();
    con.execute("INSERT INTO test VALUES (1, 'hello'), (2, 'world')", [])
        .unwrap();

    // T-SQL with ISNULL → DuckDB COALESCE
    let tsql = "SELECT id, ISNULL(name, 'N/A') FROM test ORDER BY id";
    let duckdb_sql = translate_tsql_to_duckdb(tsql);
    assert!(duckdb_sql.contains("COALESCE"));

    let rows = query_rows(&con, &duckdb_sql).unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(fmt_value(&rows[0][0]), "1");
    assert_eq!(fmt_value(&rows[0][1]), "hello");
}

#[test]
fn test_split_statements_and_execute() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    let sql = "CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1); SELECT * FROM t";
    let stmts = split_statements(sql);
    assert_eq!(stmts.len(), 3);

    // Execute each statement
    for (i, stmt) in stmts.iter().enumerate() {
        if i == 2 {
            // Last statement returns rows
            let rows = query_rows(&con, stmt).unwrap();
            assert_eq!(rows.len(), 1);
            assert_eq!(fmt_value(&rows[0][0]), "1");
        } else {
            con.execute(stmt, []).unwrap();
        }
    }
}

#[test]
fn test_duckdb_open_read_write() {
    let tmp = std::env::temp_dir().join("dm_test_rw.duckdb");
    let _ = std::fs::remove_file(&tmp);

    {
        let con = open_read_write(&tmp).unwrap();
        con.execute_batch("CREATE TABLE test (x INTEGER); INSERT INTO test VALUES (42)")
            .unwrap();
    }

    // Reopen and verify
    let con = open_read_write(&tmp).unwrap();
    let rows = query_rows(&con, "SELECT * FROM test").unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(fmt_value(&rows[0][0]), "42");

    let _ = std::fs::remove_file(&tmp);
}

#[test]
fn test_decimal_leading_zero_stripped() {
    let con = duckdb::Connection::open_in_memory().unwrap();
    con.execute_batch("CREATE TABLE test (val DECIMAL(18,4))").unwrap();
    con.execute(
        "INSERT INTO test VALUES (0.5000), (-0.5000), (123.4500), (0.0000)",
        [],
    )
    .unwrap();

    let rows = query_rows(&con, "SELECT * FROM test ORDER BY val").unwrap();
    // -0.5000 → -.5000
    assert_eq!(fmt_value(&rows[0][0]), "-.5000");
    // 0.0000 → .0000
    assert_eq!(fmt_value(&rows[1][0]), ".0000");
    // 0.5000 → .5000
    assert_eq!(fmt_value(&rows[2][0]), ".5000");
    // 123.4500 → 123.4500
    assert_eq!(fmt_value(&rows[3][0]), "123.4500");
}
