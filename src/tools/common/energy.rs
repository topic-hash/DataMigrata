//! Energy model for DuckDB and MSSQL.
//!
//! Direct port of the energy model from `scripts/verify_ops.py`:
//! ```text
//! cpu_joules   = cpu_ms * 5 / 1000
//! dram_joules  = logical_reads * 8192 * 12.5e-9
//! total_joules = cpu_joules + dram_joules
//! ```

use std::collections::HashMap;
use std::path::Path;

/// Energy result for a single operation.
#[derive(Debug, Clone)]
pub struct EnergyResult {
    pub cpu_joules: f64,
    pub dram_joules: f64,
    pub total_joules: f64,
}

/// Compute DuckDB energy from elapsed time and row count.
///
/// - `elapsed_ms`: wall-clock time in milliseconds
/// - `row_count`: number of result rows (used for logical_reads estimate)
///
/// Direct port of the energy calculation in `verify_op()` from `verify_ops.py`.
pub fn duckdb_energy(elapsed_ms: f64, row_count: usize) -> EnergyResult {
    let cpu_joules = elapsed_ms * 5.0 / 1000.0;
    let logical_reads = std::cmp::max(1, row_count / 100 + 1);
    let dram_joules = logical_reads as f64 * 8192.0 * 12.5e-9;
    let total_joules = cpu_joules + dram_joules;
    EnergyResult {
        cpu_joules,
        dram_joules,
        total_joules,
    }
}

/// Load MSSQL joules per op from `gold_standard/summary.csv`.
///
/// summary.csv columns: op_id, status, row_count, hash, elapsed_s, stderr
/// Energy model: `mssql_joules = elapsed_s * 5.0` (where cpu_ms ≈ elapsed_s * 1000).
///
/// Direct port of `load_mssql_joules()` from `verify_ops.py`.
pub fn load_mssql_joules(csv_path: &Path) -> HashMap<u32, f64> {
    let mut out = HashMap::new();
    let content = match std::fs::read_to_string(csv_path) {
        Ok(c) => c,
        Err(_) => return out,
    };

    let mut lines = content.lines();
    let header = lines.next().unwrap_or("");
    let headers: Vec<&str> = header.split(',').collect();

    // Find column indices
    let op_idx = headers
        .iter()
        .position(|h| matches!(h.trim(), "op" | "op_id" | "OpNumber"));
    let joules_idx = headers
        .iter()
        .position(|h| matches!(h.trim(), "mssql_joules" | "total_joules" | "joules"));
    let elapsed_idx = headers.iter().position(|h| h.trim() == "elapsed_s");

    for line in lines {
        let fields: Vec<&str> = line.split(',').collect();
        if fields.is_empty() {
            continue;
        }

        let op_str = op_idx
            .and_then(|i| fields.get(i).copied())
            .unwrap_or("")
            .trim();
        let op: u32 = match op_str.parse() {
            Ok(n) => n,
            Err(_) => continue,
        };

        // Prefer explicit joules column if present
        if let Some(ji) = joules_idx {
            if let Some(j_str) = fields.get(ji) {
                let j_str = j_str.trim();
                if !j_str.is_empty() {
                    if let Ok(j) = j_str.parse::<f64>() {
                        out.insert(op, j);
                        continue;
                    }
                }
            }
        }

        // Else compute from elapsed_s
        if let Some(ei) = elapsed_idx {
            if let Some(e_str) = fields.get(ei) {
                let e_str = e_str.trim();
                if !e_str.is_empty() {
                    if let Ok(elapsed) = e_str.parse::<f64>() {
                        out.insert(op, elapsed * 5.0);
                    }
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_duckdb_energy() {
        let e = duckdb_energy(10.0, 500);
        // cpu_joules = 10 * 5 / 1000 = 0.05
        assert!((e.cpu_joules - 0.05).abs() < 1e-9);
        // logical_reads = max(1, 500/100 + 1) = 6
        // dram_joules = 6 * 8192 * 12.5e-9 = 0.0006144
        assert!((e.dram_joules - 6.0 * 8192.0 * 12.5e-9).abs() < 1e-9);
    }

    #[test]
    fn test_duckdb_energy_zero_rows() {
        let e = duckdb_energy(5.0, 0);
        // logical_reads = max(1, 0) = 1
        assert!((e.dram_joules - 8192.0 * 12.5e-9).abs() < 1e-9);
    }
}
