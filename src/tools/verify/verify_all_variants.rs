//! Run verification against each schema-variant DuckDB database.
//!
//! Direct port of `scripts/verify_all_variants.py`.
//!
//! Runs `verify_ops` logic against each of the 3 variant DBs
//! (a_baseline, b_columnar, c_precomputed) and writes
//! `verification_log_{variant}.csv`.

use std::path::PathBuf;

use super::verify_ops::{run, VerifyConfig};

/// A schema variant to verify.
struct Variant {
    label: &'static str,
    db_filename: &'static str,
    log_filename: &'static str,
}

const VARIANTS: &[Variant] = &[
    Variant {
        label: "a_baseline",
        db_filename: "analytics_a.duckdb",
        log_filename: "verification_log_a_baseline.csv",
    },
    Variant {
        label: "b_columnar",
        db_filename: "analytics_b.duckdb",
        log_filename: "verification_log_b_columnar.csv",
    },
    Variant {
        label: "c_precomputed",
        db_filename: "analytics_c.duckdb",
        log_filename: "verification_log_c_precomputed.csv",
    },
];

/// Run verification for all 3 variants.
///
/// Direct port of `main()` from `verify_all_variants.py`.
pub fn run_all_variants(root: &str, op_ids: &[u32]) -> anyhow::Result<()> {
    for v in VARIANTS {
        eprintln!("\n=== Variant {} ===  db={}", v.label, v.db_filename);
        let mut config = VerifyConfig::new(root);
        config.db_path = PathBuf::from(root)
            .join("duckdb_migrated")
            .join(v.db_filename);
        config.log_path = PathBuf::from(root)
            .join("best_config")
            .join(v.log_filename);
        run(&config, op_ids, false)?;
    }
    Ok(())
}
