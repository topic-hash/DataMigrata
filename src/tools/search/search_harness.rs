//! Combinatorial optimization search — energy-optimal configuration.
//!
//! Direct port of `search_harness.py`.
//!
//! For each of the 50 operations, we have 3 rewrite alternatives (a/b/c).
//! Combined with 3 schema variants, there are 3^50 possible configurations.
//! We use a greedy heuristic: for each op independently, pick the alternative
//! that minimizes estimated energy on each schema variant.

use std::collections::HashMap;
use std::path::Path;
use std::io::Write;

/// Schema variant identifier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Variant {
    Baseline,
    Columnar,
    Precomputed,
}

impl Variant {
    fn name(&self) -> &'static str {
        match self {
            Self::Baseline => "baseline",
            Self::Columnar => "columnar",
            Self::Precomputed => "precomputed",
        }
    }

    fn all() -> &'static [Variant] {
        &[Self::Baseline, Self::Columnar, Self::Precomputed]
    }
}

/// Rewrite alternative (a/b/c).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Alternative {
    A,
    B,
    C,
}

impl Alternative {
    fn name(&self) -> &'static str {
        match self {
            Self::A => "a",
            Self::B => "b",
            Self::C => "c",
        }
    }
}

/// Energy estimate (joules) for a specific (op, variant, alternative).
fn energy_estimate(op_id: u32, variant: Variant, alt: Alternative) -> f64 {
    // Variant factor: baseline=1.0, columnar=0.5, precomputed=0.2
    let factor = match variant {
        Variant::Baseline => 1.0,
        Variant::Columnar => 0.5,
        Variant::Precomputed => 0.2,
    };
    // Alternative factor: a=1.0, b=0.8, c=0.1
    let alt_factor = match alt {
        Alternative::A => 1.0,
        Alternative::B => 0.8,
        Alternative::C => 0.1,
    };
    // Base energy per op (varies by op complexity)
    let base = base_energy(op_id);
    base * factor * alt_factor
}

/// Base energy estimate per op (from the Python ENERGY_ESTIMATES dict).
/// This is a simplified model matching the Python hardcoded values.
fn base_energy(op_id: u32) -> f64 {
    match op_id {
        1 => 0.096,
        2 => 0.200,
        3 => 0.010,
        4 => 0.150,
        5 => 0.100,
        6 => 0.050,
        7 => 0.080,
        8 => 0.050,
        9 => 0.080,
        10 => 0.001,
        11 => 0.005,
        12 => 0.100,
        13 => 0.050,
        14 => 0.005,
        15 => 0.005,
        16 => 0.010,
        17 => 0.020,
        18 => 0.010,
        19 => 0.020,
        20 => 0.020,
        21 => 0.010,
        22 => 0.030,
        23 => 0.100,
        24 => 0.010,
        25 => 0.050,
        26 => 0.200,
        27 => 0.080,
        28 => 0.150,
        29 => 0.100,
        30 => 0.080,
        31 => 0.500,
        32 => 0.100,
        33 => 0.005,
        34 => 0.080,
        35 => 0.050,
        36 => 0.030,
        37 => 0.010,
        38 => 0.010,
        39 => 0.010,
        40 => 0.050,
        41 => 0.050,
        42 => 0.050,
        43 => 0.050,
        44 => 0.005,
        45 => 0.050,
        46 => 0.020,
        47 => 0.020,
        48 => 0.010,
        49 => 0.005,
        50 => 0.020,
        _ => 0.010,
    }
}

/// Per-op configuration result.
#[derive(Debug, Clone)]
pub struct OpConfig {
    pub variant: Variant,
    pub alt: Alternative,
    pub joules: f64,
}

/// Variant-level result.
#[derive(Debug, Clone)]
pub struct VariantResult {
    pub variant: Variant,
    pub total_joules: f64,
    pub config: HashMap<u32, OpConfig>,
}

/// Find the energy-optimal configuration using greedy per-op selection.
///
/// Direct port of `find_optimal_config()` from `search_harness.py`.
pub fn find_optimal_config() -> Vec<VariantResult> {
    let mut results = Vec::new();

    for &variant in Variant::all() {
        let mut total_joules = 0.0;
        let mut config = HashMap::new();

        for op_id in 1..=50u32 {
            let alts = [Alternative::A, Alternative::B, Alternative::C];
            let mut best_alt = Alternative::A;
            let mut best_j = f64::MAX;
            for alt in &alts {
                let j = energy_estimate(op_id, variant, *alt);
                if j < best_j {
                    best_j = j;
                    best_alt = *alt;
                }
            }
            total_joules += best_j;
            config.insert(
                op_id,
                OpConfig {
                    variant,
                    alt: best_alt,
                    joules: best_j,
                },
            );
        }

        results.push(VariantResult {
            variant,
            total_joules,
            config,
        });
    }

    // Sort by total joules (ascending)
    results.sort_by(|a, b| {
        a.total_joules
            .partial_cmp(&b.total_joules)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    results
}

/// Run the search harness and write results.
///
/// Direct port of `main()` from `search_harness.py`.
pub fn run(out_dir: &Path) -> anyhow::Result<()> {
    const MSSQL_TOTAL: f64 = 2720.27;

    println!("{}", "=".repeat(70));
    println!("Combinatorial Optimization Search — Energy-Optimal Configuration");
    println!("{}", "=".repeat(70));

    let results = find_optimal_config();

    std::fs::create_dir_all(out_dir)?;

    // Write search results CSV
    let search_csv = out_dir.join("search_results.csv");
    let mut f = std::fs::File::create(&search_csv)?;
    writeln!(
        f,
        "rank,schema_variant,total_joules,mssql_baseline_joules,speedup"
    )?;
    for (i, r) in results.iter().enumerate() {
        let speedup = if r.total_joules > 0.0 {
            MSSQL_TOTAL / r.total_joules
        } else {
            f64::INFINITY
        };
        writeln!(
            f,
            "{},{},{:.4},{},{:.0}x",
            i + 1,
            r.variant.name(),
            r.total_joules,
            MSSQL_TOTAL,
            speedup,
        )?;
    }

    // Write per-op config for top 3
    for (i, r) in results.iter().take(3).enumerate() {
        let config_path = out_dir.join(format!("config_{}_{}.csv", i + 1, r.variant.name()));
        let mut cf = std::fs::File::create(&config_path)?;
        writeln!(
            cf,
            "op_id,schema_variant,rewrite_alternative,estimated_joules"
        )?;
        for op_id in 1..=50u32 {
            if let Some(c) = r.config.get(&op_id) {
                writeln!(
                    cf,
                    "{},{},{},{:.6}",
                    op_id,
                    c.variant.name(),
                    c.alt.name(),
                    c.joules,
                )?;
            }
        }
    }

    // Print summary
    println!("\nTop 3 configurations (by total estimated joules):\n");
    for (i, r) in results.iter().take(3).enumerate() {
        let speedup = MSSQL_TOTAL / r.total_joules;
        println!(
            "  #{}: {:15} — {:.4} J ({:.0}x faster than MSSQL)",
            i + 1,
            r.variant.name(),
            r.total_joules,
            speedup,
        );
    }

    println!("\nMSSQL baseline: {} J", MSSQL_TOTAL);
    println!("Best DuckDB config: {:.4} J", results[0].total_joules);
    println!(
        "Energy reduction: {:.2}% of MSSQL",
        results[0].total_joules / MSSQL_TOTAL * 100.0
    );

    // Per-op detail for best config
    let best = &results[0];
    println!("\nBest configuration: {}", best.variant.name());
    println!("Per-op energy breakdown:");
    for op_id in 1..=50u32 {
        if let Some(c) = best.config.get(&op_id) {
            println!("  OP {:02}: alt={}  {:.6} J", op_id, c.alt.name(), c.joules);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_optimal_config_returns_3_variants() {
        let results = find_optimal_config();
        assert_eq!(results.len(), 3);
    }

    #[test]
    fn test_results_sorted_ascending() {
        let results = find_optimal_config();
        assert!(results[0].total_joules <= results[1].total_joules);
        assert!(results[1].total_joules <= results[2].total_joules);
    }

    #[test]
    fn test_precomputed_is_best() {
        let results = find_optimal_config();
        assert_eq!(results[0].variant, Variant::Precomputed);
    }

    #[test]
    fn test_all_50_ops_in_config() {
        let results = find_optimal_config();
        for r in &results {
            assert_eq!(r.config.len(), 50);
        }
    }
}
