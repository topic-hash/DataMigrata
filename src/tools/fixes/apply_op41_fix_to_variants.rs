//! Apply op41 SensitiveData fix to all 3 schema variant DBs.
//!
//! Direct port of `scripts/apply_op41_fix_to_variants.py`.

use std::path::Path;

use super::fix_op41_sensitive_data::apply_fix;

/// Apply the op41 fix to all 3 variant databases.
///
/// Direct port of `main()` from `apply_op41_fix_to_variants.py`.
pub fn apply_to_all_variants(root: &str) -> anyhow::Result<()> {
    let gold_path = std::path::PathBuf::from(root).join("gold_standard/op_41.csv");
    let variants = [
        ("a_baseline", "duckdb_migrated/analytics_a.duckdb"),
        ("b_columnar", "duckdb_migrated/analytics_b.duckdb"),
        ("c_precomputed", "duckdb_migrated/analytics_c.duckdb"),
    ];

    for (label, db_sub) in &variants {
        let db_path = Path::new(root).join(db_sub);
        eprintln!("Applying op41 fix to {} ({})", label, db_path.display());
        apply_fix(&db_path, &gold_path)?;
    }

    eprintln!("\nAll 3 variant DBs updated.");
    Ok(())
}
