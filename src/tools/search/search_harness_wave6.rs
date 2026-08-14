//! Wave 6: Combinatorial optimization search with DuckDB execution.
//!
//! Direct port of `scripts/search_harness_wave6.py`.
//!
//! For each of the 50 operations, try multiple configurations:
//! - Schema variant: A (baseline), B (columnar), C (precomputed)
//! - Rewrite alternative: where available, _a/_b/_c SQL variants
//!
//! Measure energy for each (op, schema, rewrite) combination.
//! Find the global energy-optimal configuration.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::io::Write;
use std::time::Instant;

use regex::Regex;

use super::super::common::csv_norm::{md5_of_text, normalize_csv_text};
use super::super::common::duckdb_conn::open_read_only;
use super::super::common::energy::{duckdb_energy, load_mssql_joules};
use super::super::common::sql_translate::translate_tsql_to_duckdb;
use super::super::common::value_fmt::rows_to_csv;

/// Configuration for the wave 6 search.
#[derive(Debug, Clone)]
pub struct SearchConfig {
    pub root: PathBuf,
    pub gold_dir: PathBuf,
    pub out_csv: PathBuf,
    pub db_variants: HashMap<char, PathBuf>,
}

impl SearchConfig {
    pub fn new(root: &str) -> Self {
        let root_pb = PathBuf::from(root);
        let mut db_variants = HashMap::new();
        db_variants.insert('A', root_pb.join("duckdb_migrated/analytics_a.duckdb"));
        db_variants.insert('B', root_pb.join("duckdb_migrated/analytics_b.duckdb"));
        db_variants.insert('C', root_pb.join("duckdb_migrated/analytics_c.duckdb"));
        Self {
            root: root_pb.clone(),
            gold_dir: root_pb.join("gold_standard"),
            out_csv: root_pb.join("best_config/search_results.csv"),
            db_variants,
        }
    }
}

/// Find available SQL alternatives for an op.
///
/// Returns list of (label, sql_path).
///
/// Direct port of `find_alternatives()` from `search_harness_wave6.py`.
fn find_alternatives(op_id: u32, root: &Path) -> Vec<(String, PathBuf)> {
    let mut alts = vec![(
        "default".to_string(),
        root.join(format!("best_config/op_{:02}.sql", op_id)),
    )];
    for suffix in ['a', 'b', 'c'] {
        let p = root.join(format!("duckdb_migrated/op_{:02}_{}.sql", op_id, suffix));
        if p.exists() {
            alts.push((format!("alt_{}", suffix), p));
        }
    }
    alts
}

/// Measurement result for a single (op, schema, rewrite) combination.
struct Measurement {
    status: String,
    joules: f64,
    #[allow(dead_code)]
    hash: String,
    #[allow(dead_code)]
    rows: usize,
}

/// Execute SQL against db_path, return (status, joules, hash, rows).
///
/// Direct port of `measure_op()` from `search_harness_wave6.py`.
fn measure_op(db_path: &Path, sql_path: &Path, gold_dir: &Path) -> Measurement {
    if !sql_path.exists() {
        return Measurement {
            status: "NO_SQL".into(),
            joules: 0.0,
            hash: String::new(),
            rows: 0,
        };
    }

    let raw_sql = std::fs::read_to_string(sql_path).unwrap_or_default();
    let sql = translate_tsql_to_duckdb(&raw_sql);

    let con = match open_read_only(db_path) {
        Ok(c) => c,
        Err(e) => {
            return Measurement {
                status: format!("EXEC_FAIL: {}", &e.to_string()[..60]),
                joules: 0.0,
                hash: String::new(),
                rows: 0,
            }
        }
    };

    let t0 = Instant::now();
    let mut rows: Vec<Vec<duckdb::types::Value>> = Vec::new();
    let mut status = "EXEC_OK".to_string();

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
                        Ok(r) => rows = r,
                        Err(e) => status = format!("EXEC_FAIL: {}", &e.to_string()[..60]),
                    }
                }
                Err(e) => status = format!("EXEC_FAIL: {}", &e.to_string()[..60]),
            }
        }
        Err(e) => status = format!("EXEC_FAIL: {}", &e.to_string()[..60]),
    }

    let elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0;
    let energy = duckdb_energy(elapsed_ms, rows.len());

    // Compute hash
    let duck_csv = rows_to_csv(&rows);
    let duck_norm = normalize_csv_text(&duck_csv);
    let duck_hash = md5_of_text(&duck_norm);

    // Extract op_id from filename and compare to gold
    let re = Regex::new(r"op_(\d+)").unwrap();
    if let Some(caps) = re.captures(&sql_path.to_string_lossy()) {
        let op_id: u32 = caps[1].parse().unwrap_or(0);
        let gold_path = gold_dir.join(format!("op_{:02}.csv", op_id));
        if gold_path.exists() {
            let gold_text = std::fs::read_to_string(&gold_path).unwrap_or_default();
            let gold_norm = normalize_csv_text(&gold_text);
            let gold_hash = md5_of_text(&gold_norm);
            if duck_hash == gold_hash {
                status = "PASS".into();
            } else {
                status = "MISMATCH".into();
            }
        } else {
            status = "NO_GOLD".into();
        }
    }

    Measurement {
        status,
        joules: energy.total_joules,
        hash: duck_hash,
        rows: rows.len(),
    }
}

/// Per-op search result.
struct OpSearchResult {
    op_id: u32,
    best_schema: String,
    best_rewrite: String,
    best_duckdb_joules: String,
    mssql_joules: String,
    energy_reduction_x: String,
    all_alternatives_tested: usize,
    status: String,
}

/// Run the wave 6 search.
///
/// Direct port of `main()` from `search_harness_wave6.py`.
pub fn run(config: &SearchConfig) -> anyhow::Result<()> {
    let mssql_joules_csv = config.gold_dir.join("summary.csv");
    let mssql_joules = load_mssql_joules(&mssql_joules_csv);

    println!("Wave 6: Combinatorial Search");
    println!("{}", "=".repeat(80));

    let mut results = Vec::new();
    let mut pass_count = 0;

    for op_id in 1..=50u32 {
        let alts = find_alternatives(op_id, &config.root);
        let mut best: Option<(f64, char, String, String)> = None; // (joules, schema, rewrite, status)
        let mut all_count = 0;

        for (&schema, db_path) in &config.db_variants {
            for (rewrite_label, sql_path) in &alts {
                let m = measure_op(db_path, sql_path, &config.gold_dir);
                all_count += 1;
                if m.status == "PASS" {
                    if best.is_none() || m.joules < best.as_ref().unwrap().0 {
                        best = Some((m.joules, schema, rewrite_label.clone(), m.status.clone()));
                    }
                }
            }
        }

        if let Some((best_j, best_s, best_r, _)) = best {
            pass_count += 1;
            let mssql_j = mssql_joules.get(&op_id).copied().unwrap_or(0.0);
            let reduction = if best_j > 0.0 && mssql_j > 0.0 {
                mssql_j / best_j
            } else {
                0.0
            };
            println!(
                "  op {:02}: PASS  schema={}  rewrite={}  joules={:.4}  reduction={:.1}x  ({} alternatives tested)",
                op_id, best_s, best_r, best_j, reduction, all_count
            );
            results.push(OpSearchResult {
                op_id,
                best_schema: best_s.to_string(),
                best_rewrite: best_r,
                best_duckdb_joules: format!("{:.6}", best_j),
                mssql_joules: if mssql_j > 0.0 { format!("{:.6}", mssql_j) } else { String::new() },
                energy_reduction_x: if reduction > 0.0 { format!("{:.1}", reduction) } else { String::new() },
                all_alternatives_tested: all_count,
                status: "PASS".into(),
            });
        } else {
            results.push(OpSearchResult {
                op_id,
                best_schema: String::new(),
                best_rewrite: String::new(),
                best_duckdb_joules: String::new(),
                mssql_joules: String::new(),
                energy_reduction_x: String::new(),
                all_alternatives_tested: all_count,
                status: "FAIL".into(),
            });
            println!("  op {:02}: FAIL  ({} alternatives tested)", op_id, all_count);
        }
    }

    // Write CSV
    if let Some(parent) = config.out_csv.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut f = std::fs::File::create(&config.out_csv)?;
    writeln!(
        f,
        "op_id,best_schema,best_rewrite,best_duckdb_joules,mssql_joules,energy_reduction_x,all_alternatives_tested,status"
    )?;
    for r in &results {
        writeln!(
            f,
            "{},{},{},{},{},{},{},{}",
            r.op_id,
            r.best_schema,
            r.best_rewrite,
            r.best_duckdb_joules,
            r.mssql_joules,
            r.energy_reduction_x,
            r.all_alternatives_tested,
            r.status,
        )?;
    }

    println!("\n{}", "=".repeat(80));
    println!("RESULT: {}/50 ops have at least one PASS configuration", pass_count);
    println!("Search results: {}", config.out_csv.display());

    // Compute total energy
    let total_duck: f64 = results
        .iter()
        .filter(|r| r.status == "PASS")
        .filter_map(|r| r.best_duckdb_joules.parse::<f64>().ok())
        .sum();
    let total_mssql: f64 = results
        .iter()
        .filter_map(|r| r.mssql_joules.parse::<f64>().ok())
        .sum();
    println!("\nTotal DuckDB energy (optimal): {:.4} J", total_duck);
    println!("Total MSSQL energy:            {:.4} J", total_mssql);
    if total_duck > 0.0 && total_mssql > 0.0 {
        println!("Overall energy reduction:      {:.1}x", total_mssql / total_duck);
    }

    // Schema distribution
    let mut schema_counts: HashMap<char, usize> = HashMap::new();
    for r in &results {
        if r.status == "PASS" && !r.best_schema.is_empty() {
            *schema_counts.entry(r.best_schema.chars().next().unwrap_or('?')).or_insert(0) += 1;
        }
    }
    println!(
        "\nOptimal schema distribution: A={}, B={}, C={}",
        schema_counts.get(&'A').copied().unwrap_or(0),
        schema_counts.get(&'B').copied().unwrap_or(0),
        schema_counts.get(&'C').copied().unwrap_or(0),
    );

    Ok(())
}
