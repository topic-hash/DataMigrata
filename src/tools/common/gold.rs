//! Gold-standard comparison logic.
//!
//! Direct port of `verify_op()` from `scripts/verify_ops.py`.
//!
//! For each op:
//! 1. Apply T-SQL → DuckDB dialect translation
//! 2. Execute against DuckDB
//! 3. Format result rows to match MSSQL bcp CSV
//! 4. MD5 of normalized CSV
//! 5. Compare to gold standard

use std::path::Path;
use std::time::Instant;

use super::csv_norm::{md5_of_text, normalize_csv_text};
use super::energy::duckdb_energy;
use super::sql_translate::{split_statements, translate_tsql_to_duckdb};
use super::value_fmt::rows_to_csv;

/// Verification status for a single op.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VerifyStatus {
    Pass,
    Mismatch,
    ExecFail,
    NoSql,
    NoGold,
}

impl std::fmt::Display for VerifyStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Pass => write!(f, "PASS"),
            Self::Mismatch => write!(f, "MISMATCH"),
            Self::ExecFail => write!(f, "EXEC_FAIL"),
            Self::NoSql => write!(f, "NO_SQL"),
            Self::NoGold => write!(f, "NO_GOLD"),
        }
    }
}

/// Result of verifying a single op.
#[derive(Debug, Clone)]
pub struct VerifyResult {
    pub op_id: u32,
    pub status: VerifyStatus,
    pub duck_hash: String,
    pub gold_hash: String,
    pub duck_rows: usize,
    pub gold_rows: usize,
    pub error: String,
    pub joules: f64,
}

/// Verify a single op against the gold standard.
///
/// Direct port of `verify_op()` from `verify_ops.py`.
///
/// - `con`: open DuckDB connection (read-only)
/// - `op_id`: operation number (1-50)
/// - `ops_dir`: directory containing `op_NN.sql` files
/// - `gold_dir`: directory containing `op_NN.csv` gold standard files
pub fn verify_op(
    con: &duckdb::Connection,
    op_id: u32,
    ops_dir: &Path,
    gold_dir: &Path,
) -> VerifyResult {
    let sql_path = ops_dir.join(format!("op_{:02}.sql", op_id));
    let gold_path = gold_dir.join(format!("op_{:02}.csv", op_id));

    if !sql_path.exists() {
        return VerifyResult {
            op_id,
            status: VerifyStatus::NoSql,
            duck_hash: String::new(),
            gold_hash: String::new(),
            duck_rows: 0,
            gold_rows: 0,
            error: format!("missing {}", sql_path.display()),
            joules: 0.0,
        };
    }
    if !gold_path.exists() {
        return VerifyResult {
            op_id,
            status: VerifyStatus::NoGold,
            duck_hash: String::new(),
            gold_hash: String::new(),
            duck_rows: 0,
            gold_rows: 0,
            error: format!("missing {}", gold_path.display()),
            joules: 0.0,
        };
    }

    let raw_sql = std::fs::read_to_string(&sql_path).unwrap_or_default();
    let sql = translate_tsql_to_duckdb(&raw_sql);
    let stmts = split_statements(&sql);

    let t0 = Instant::now();
    let mut rows: Vec<Vec<duckdb::types::Value>> = Vec::new();
    let mut err: Option<String> = None;

    for (i, stmt) in stmts.iter().enumerate() {
        match con.prepare(stmt) {
            Ok(mut cur) => {
                // Try to fetch — if this statement doesn't return rows, query returns empty
                match cur.query_map([], |row| {
                    let mut values = Vec::new();
                    let col_count = row.as_ref().column_count();
                    for j in 0..col_count {
                        let val: duckdb::types::Value = row.get(j)?;
                        values.push(val);
                    }
                    Ok(values)
                }) {
                    Ok(mapped) => {
                        let collected: Result<Vec<_>, _> = mapped.collect();
                        match collected {
                            Ok(rs) => {
                                if i == stmts.len() - 1 || !rs.is_empty() {
                                    rows = rs;
                                }
                            }
                            Err(e) => {
                                if i == stmts.len() - 1 {
                                    err = Some(e.to_string());
                                }
                            }
                        }
                    }
                    Err(e) => {
                        if i == stmts.len() - 1 {
                            err = Some(e.to_string());
                        }
                    }
                }
            }
            Err(e) => {
                if i == stmts.len() - 1 {
                    err = Some(e.to_string());
                }
            }
        }
    }

    let elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0;
    let energy = duckdb_energy(elapsed_ms, rows.len());

    if let Some(e) = err {
        let first_line = e.lines().next().unwrap_or(&e).to_string();
        return VerifyResult {
            op_id,
            status: VerifyStatus::ExecFail,
            duck_hash: String::new(),
            gold_hash: String::new(),
            duck_rows: 0,
            gold_rows: 0,
            error: first_line.chars().take(200).collect(),
            joules: energy.total_joules,
        };
    }

    let duck_csv = rows_to_csv(&rows);
    let duck_norm = normalize_csv_text(&duck_csv);
    let duck_hash = md5_of_text(&duck_norm);

    let gold_text = std::fs::read_to_string(&gold_path).unwrap_or_default();
    let gold_norm = normalize_csv_text(&gold_text);
    let gold_hash = md5_of_text(&gold_norm);

    let gold_lines: Vec<&str> = if gold_norm.trim().is_empty() {
        Vec::new()
    } else {
        gold_norm.trim().split('\n').collect()
    };
    let duck_lines: Vec<&str> = if duck_norm.trim().is_empty() {
        Vec::new()
    } else {
        duck_norm.trim().split('\n').collect()
    };

    if duck_hash == gold_hash {
        return VerifyResult {
            op_id,
            status: VerifyStatus::Pass,
            duck_hash,
            gold_hash,
            duck_rows: duck_lines.len(),
            gold_rows: gold_lines.len(),
            error: String::new(),
            joules: energy.total_joules,
        };
    }

    // Find first differing line
    let max_len = duck_lines.len().max(gold_lines.len());
    let mut diff = String::new();
    for i in 0..max_len {
        let d = duck_lines.get(i).copied().unwrap_or("<missing>");
        let g = gold_lines.get(i).copied().unwrap_or("<missing>");
        if d != g {
            let d_trunc: String = d.chars().take(140).collect();
            let g_trunc: String = g.chars().take(140).collect();
            diff = format!("line {}: duck={} | gold={}", i, d_trunc, g_trunc);
            break;
        }
    }
    if diff.is_empty() {
        diff = format!("row count differs: duck={} gold={}", duck_lines.len(), gold_lines.len());
    }

    VerifyResult {
        op_id,
        status: VerifyStatus::Mismatch,
        duck_hash,
        gold_hash,
        duck_rows: duck_lines.len(),
        gold_rows: gold_lines.len(),
        error: diff,
        joules: energy.total_joules,
    }
}
