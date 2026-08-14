//! Test the current state of all 50 ops against the gold standard.
//!
//! Direct port of `scripts/test_current_state.py`.
//!
//! Simpler than `verify_ops` — runs DuckDB SQL files and compares MD5
//! hashes against gold standard CSVs. Superseded by `verify_ops`.

use std::path::Path;
use std::io::Write;

use regex::Regex;

use super::super::common::csv_norm::md5_of_text;
use super::super::common::duckdb_conn::open_read_only;
use super::super::common::value_fmt::fmt_value;

/// Hash DuckDB rows in a deterministic way matching MSSQL gold standard format.
///
/// Direct port of `hash_csv()` from `test_current_state.py`.
fn hash_csv(rows: &[Vec<duckdb::types::Value>]) -> String {
    if rows.is_empty() {
        return String::new();
    }
    let mut lines = Vec::new();
    for r in rows {
        let vals: Vec<String> = r
            .iter()
            .map(|v| match v {
                duckdb::types::Value::Null => String::new(),
                duckdb::types::Value::Boolean(b) => {
                    if *b {
                        "1".into()
                    } else {
                        "0".into()
                    }
                }
                _ => fmt_value(v),
            })
            .collect();
        lines.push(vals.join(","));
    }
    md5_of_text(&lines.join("\n"))
}

/// Hash the gold standard CSV file (raw text).
///
/// Direct port of `hash_gold_csv()` from `test_current_state.py`.
fn hash_gold_csv(path: &Path) -> Option<String> {
    if !path.exists() {
        return None;
    }
    let content = std::fs::read(path).ok()?;
    Some(md5_of_text(&String::from_utf8_lossy(&content)))
}

/// Run a single SQL op, return (rows, error).
///
/// Direct port of `run_op()` from `test_current_state.py`.
fn run_op(con: &duckdb::Connection, sql_text: &str) -> (Option<Vec<Vec<duckdb::types::Value>>>, Option<String>) {
    // Remove GO and trailing semicolons
    let go_re = Regex::new(r"(?i)\bGO\b").unwrap();
    let mut sql = go_re.replace_all(sql_text, "").into_owned();
    sql = sql.trim().trim_end_matches(';').trim().to_string();

    match con.prepare(&sql) {
        Ok(mut stmt) => {
            match stmt.query_map([], |row| {
                let mut values = Vec::new();
                let col_count = row.as_ref().column_count();
                for i in 0..col_count {
                    let val: duckdb::types::Value = row.get(i)?;
                    values.push(val);
                }
                Ok(values)
            }) {
                Ok(mapped) => {
                    let collected: Result<Vec<_>, _> = mapped.collect();
                    match collected {
                        Ok(rows) => (Some(rows), None),
                        Err(e) => (None, Some(e.to_string())),
                    }
                }
                Err(e) => (None, Some(e.to_string())),
            }
        }
        Err(e) => (None, Some(e.to_string())),
    }
}

/// Test result for a single op.
struct TestResult {
    op_num: u32,
    status: String,
    duck_rows: usize,
    gold_rows: usize,
    hash: String,
    error: String,
}

/// Run the current-state test for all 50 ops.
///
/// Direct port of `main()` from `test_current_state.py`.
pub fn run(db_path: &Path, migrated_dir: &Path, gold_dir: &Path, out_csv: &Path) -> anyhow::Result<()> {
    let con = open_read_only(db_path)?;
    let mut results = Vec::new();

    for op_num in 1..=50u32 {
        let op_id = format!("op_{:02}", op_num);
        let sql_file = migrated_dir.join(format!("{}.sql", op_id));
        let gold_file = gold_dir.join(format!("{}.csv", op_id));

        let gold_hash = hash_gold_csv(&gold_file);
        let gold_rows = if gold_file.exists() {
            std::fs::read_to_string(&gold_file)?.lines().count()
        } else {
            0
        };

        if !sql_file.exists() {
            results.push(TestResult {
                op_num,
                status: "NO_SQL_FILE".into(),
                duck_rows: 0,
                gold_rows,
                hash: String::new(),
                error: String::new(),
            });
            continue;
        }

        let sql_text = std::fs::read_to_string(&sql_file)?;
        let (rows, err) = run_op(&con, &sql_text);

        if let Some(e) = err {
            let err_preview: String = e.chars().take(120).collect();
            results.push(TestResult {
                op_num,
                status: "EXEC_FAIL".into(),
                duck_rows: 0,
                gold_rows,
                hash: String::new(),
                error: err_preview,
            });
        } else if let Some(rows) = rows {
            let duck_hash = hash_csv(&rows);
            // Compare against gold hash
            let status = match &gold_hash {
                Some(gh) if *gh == duck_hash => "PASS",
                Some(_) => "MISMATCH",
                None => "NO_GOLD",
            };
            let hash_preview: String = duck_hash.chars().take(16).collect();
            results.push(TestResult {
                op_num,
                status: status.into(),
                duck_rows: rows.len(),
                gold_rows,
                hash: hash_preview,
                error: String::new(),
            });
        }
    }

    // Print results
    let pass_count = results.iter().filter(|r| r.status == "PASS").count();
    println!("TOTAL: {}/50 PASS\n", pass_count);
    println!("{:>3} {:<12} {:>6} {:>6} {:<20} ERROR", "OP", "STATUS", "ROWS", "GOLD", "HASH");
    for r in &results {
        println!(
            "{:>3} {:<12} {:>6} {:>6} {:<20} {}",
            r.op_num, r.status, r.duck_rows, r.gold_rows, r.hash, r.error
        );
    }

    // Write to file
    if let Some(parent) = out_csv.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut f = std::fs::File::create(out_csv)?;
    writeln!(f, "op,status,duck_rows,gold_rows,error")?;
    for r in &results {
        let err_preview: String = r.error.chars().take(200).collect();
        writeln!(f, "{},{},{},{},\"{}\"", r.op_num, r.status, r.duck_rows, r.gold_rows, err_preview)?;
    }

    Ok(())
}
