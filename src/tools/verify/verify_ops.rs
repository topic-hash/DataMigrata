//! Unified verification harness for DataMigrata.
//!
//! Direct port of `scripts/verify_ops.py`.
//!
//! For each op_NN.sql in `best_config/`:
//! 1. Apply minimal T-SQL → DuckDB dialect translation
//! 2. Execute against `analytics.duckdb`
//! 3. Capture result rows
//! 4. Format each value to match MSSQL gold-standard CSV format
//! 5. MD5 of normalized CSV
//! 6. Compare to `gold_standard/op_NN.csv`
//! 7. Append row to `verification_log.csv`

use std::path::{Path, PathBuf};

use super::super::common::duckdb_conn::open_read_only;
use super::super::common::energy::load_mssql_joules;
use super::super::common::gold::{verify_op, VerifyResult, VerifyStatus};

/// Configuration for the verification harness.
#[derive(Debug, Clone)]
pub struct VerifyConfig {
    pub db_path: PathBuf,
    pub ops_dir: PathBuf,
    pub gold_dir: PathBuf,
    pub log_path: PathBuf,
    pub mssql_joules_csv: PathBuf,
}

impl VerifyConfig {
    /// Create a config with the default project root (`/home/z/my-project`).
    pub fn new(root: &str) -> Self {
        Self {
            db_path: PathBuf::from(root).join("duckdb_migrated/analytics.duckdb"),
            ops_dir: PathBuf::from(root).join("best_config"),
            gold_dir: PathBuf::from(root).join("gold_standard"),
            log_path: PathBuf::from(root).join("best_config/verification_log.csv"),
            mssql_joules_csv: PathBuf::from(root).join("gold_standard/summary.csv"),
        }
    }
}

/// Run the verification harness for the given ops.
///
/// - `op_ids`: ops to verify (1-50); empty means all 50
/// - `verbose`: print first-row diff on mismatch
///
/// Direct port of `main()` from `verify_ops.py`.
pub fn run(config: &VerifyConfig, op_ids: &[u32], verbose: bool) -> anyhow::Result<Vec<VerifyResult>> {
    let ops: Vec<u32> = if op_ids.is_empty() {
        (1..=50).collect()
    } else {
        op_ids.to_vec()
    };

    let mssql_joules = load_mssql_joules(&config.mssql_joules_csv);
    let con = open_read_only(&config.db_path)?;

    let mut results = Vec::new();
    let mut pass_count = 0;

    for &op_id in &ops {
        let result = verify_op(&con, op_id, &config.ops_dir, &config.gold_dir);

        if result.status == VerifyStatus::Pass {
            pass_count += 1;
        }

        let marker = if result.status == VerifyStatus::Pass { "PASS" } else { "FAIL" };
        let err_preview: String = result.error.chars().take(100).collect();
        eprintln!(
            "{} op {:02}: {}  rows={}/{}  duckdb_j={:.4}  err={}",
            if result.status == VerifyStatus::Pass { "+" } else { "x" },
            op_id,
            marker,
            result.duck_rows,
            result.gold_rows,
            result.joules,
            err_preview,
        );

        if verbose && result.status == VerifyStatus::Mismatch {
            eprintln!("  diff: {}", result.error);
        }

        results.push(result);
    }

    // Write verification log CSV
    write_log(&config.log_path, &results, &mssql_joules)?;

    eprintln!("\n=== RESULT: {}/{} PASS ===", pass_count, ops.len());
    eprintln!("Log: {}", config.log_path.display());

    Ok(results)
}

/// Write the verification log CSV.
///
/// Direct port of the CSV-writing block in `main()` from `verify_ops.py`.
fn write_log(
    log_path: &Path,
    results: &[VerifyResult],
    mssql_joules: &std::collections::HashMap<u32, f64>,
) -> anyhow::Result<()> {
    use std::io::Write;
    if let Some(parent) = log_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut f = std::fs::File::create(log_path)?;
    writeln!(
        f,
        "op_id,status,duck_rows,gold_rows,duck_hash,gold_hash,duckdb_joules,mssql_joules,energy_reduction_x,error"
    )?;
    for r in results {
        let mssql_j = mssql_joules.get(&r.op_id).copied().unwrap_or(0.0);
        let reduction = if r.joules > 0.0 && mssql_j > 0.0 {
            mssql_j / r.joules
        } else {
            0.0
        };
        let mssql_str = if mssql_j > 0.0 { format!("{:.6}", mssql_j) } else { String::new() };
        let reduction_str = if reduction > 0.0 { format!("{:.1}", reduction) } else { String::new() };
        writeln!(
            f,
            "{},{},{},{},{},{},{:.6},{},{},{}",
            r.op_id,
            r.status,
            r.duck_rows,
            r.gold_rows,
            r.duck_hash,
            r.gold_hash,
            r.joules,
            mssql_str,
            reduction_str,
            csv_escape(&r.error),
        )?;
    }
    Ok(())
}

fn csv_escape(s: &str) -> String {
    if s.contains(',') || s.contains('"') || s.contains('\n') {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}
