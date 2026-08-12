#!/usr/bin/env python3
"""
Wave 6: Combinatorial optimization search.

For each of the 50 operations, try multiple configurations:
  - Schema variant: A (baseline), B (columnar), C (precomputed)
  - Rewrite alternative: where available, _a/_b/_c SQL variants in duckdb_migrated/

Measure energy for each (op, schema, rewrite) combination.
Find the global energy-optimal configuration.

Output: best_config/search_results.csv with columns:
  op_id, best_schema, best_rewrite, best_duckdb_joules, mssql_joules, energy_reduction_x, all_alternatives_tested
"""
import duckdb
import csv
import os
import time
import hashlib
import re
from decimal import Decimal
import datetime

ROOT = "/home/z/my-project"
GOLD_DIR = f"{ROOT}/gold_standard"
OUT_CSV = f"{ROOT}/best_config/search_results.csv"
DB_VARIANTS = {
    "A": f"{ROOT}/duckdb_migrated/analytics_a.duckdb",
    "B": f"{ROOT}/duckdb_migrated/analytics_b.duckdb",
    "C": f"{ROOT}/duckdb_migrated/analytics_c.duckdb",
}

# Import the verifier's translation and formatting functions
import sys
sys.path.insert(0, f"{ROOT}/scripts")
from verify_ops import (
    translate_tsql_to_duckdb, fmt_value, rows_to_csv, normalize_csv_text, md5_of_text,
    load_mssql_joules, _normalize_dt_str
)


def find_alternatives(op_id):
    """Find available SQL alternatives for an op. Returns list of (label, sql_path)."""
    alts = [("default", f"{ROOT}/best_config/op_{op_id:02d}.sql")]
    # Look for _a, _b, _c variants in duckdb_migrated/
    for suffix in ["a", "b", "c"]:
        p = f"{ROOT}/duckdb_migrated/op_{op_id:02d}_{suffix}.sql"
        if os.path.exists(p):
            alts.append((f"alt_{suffix}", p))
    return alts


def measure_op(db_path, sql_path):
    """Execute SQL against db_path, return (status, joules, hash, rows)."""
    if not os.path.exists(sql_path):
        return ("NO_SQL", 0.0, "", 0)
    raw_sql = open(sql_path).read()
    sql = translate_tsql_to_duckdb(raw_sql)
    
    con = duckdb.connect(db_path, read_only=True)
    t0 = time.perf_counter()
    try:
        cur = con.cursor()
        cur.execute(sql)
        rows = cur.fetchall()
        status = "EXEC_OK"
    except Exception as e:
        rows = []
        status = f"EXEC_FAIL: {str(e)[:60]}"
    elapsed_ms = (time.perf_counter() - t0) * 1000
    cpu_joules = elapsed_ms * 5 / 1000
    logical_reads = max(1, len(rows) // 100 + 1)
    dram_joules = logical_reads * 8192 * 12.5e-9
    joules = cpu_joules + dram_joules
    
    # Compute hash
    duck_csv = rows_to_csv(rows)
    duck_norm = normalize_csv_text(duck_csv)
    duck_hash = md5_of_text(duck_norm)
    
    # Compare to gold (op_id extracted from filename)
    op_id = int(re.search(r'op_(\d+)', sql_path).group(1))
    gold_path = f"{GOLD_DIR}/op_{op_id:02d}.csv"
    if os.path.exists(gold_path):
        with open(gold_path, "rb") as f:
            gold_text = f.read().decode("utf-8", errors="replace")
        gold_norm = normalize_csv_text(gold_text)
        gold_hash = md5_of_text(gold_norm)
        if duck_hash == gold_hash:
            status = "PASS"
        else:
            status = "MISMATCH"
    else:
        status = "NO_GOLD"
    
    con.close()
    return (status, joules, duck_hash, len(rows))


def main():
    mssql_joules = load_mssql_joules()
    
    print("Wave 6: Combinatorial Search")
    print("=" * 80)
    
    results = []
    pass_count = 0
    
    for op_id in range(1, 51):
        alts = find_alternatives(op_id)
        best = None  # (joules, schema, rewrite, status)
        all_results = []
        
        for schema, db_path in DB_VARIANTS.items():
            for rewrite_label, sql_path in alts:
                status, joules, h, n = measure_op(db_path, sql_path)
                all_results.append((schema, rewrite_label, status, joules))
                if status == "PASS":
                    if best is None or joules < best[0]:
                        best = (joules, schema, rewrite_label, status)
        
        if best:
            pass_count += 1
            best_j, best_s, best_r, best_st = best
            mssql_j = mssql_joules.get(op_id, 0.0)
            reduction = (mssql_j / best_j) if best_j > 0 and mssql_j > 0 else 0
            n_alts = len(all_results)
            results.append({
                "op_id": op_id,
                "best_schema": best_s,
                "best_rewrite": best_r,
                "best_duckdb_joules": f"{best_j:.6f}",
                "mssql_joules": f"{mssql_j:.6f}" if mssql_j else "",
                "energy_reduction_x": f"{reduction:.1f}" if reduction else "",
                "all_alternatives_tested": n_alts,
                "status": "PASS",
            })
            print(f"  op {op_id:02d}: PASS  schema={best_s}  rewrite={best_r}  joules={best_j:.4f}  reduction={reduction:.1f}x  ({n_alts} alternatives tested)")
        else:
            # No PASS — pick lowest-joules attempt
            lowest = min(all_results, key=lambda x: x[3]) if all_results else None
            results.append({
                "op_id": op_id,
                "best_schema": lowest[0] if lowest else "",
                "best_rewrite": lowest[1] if lowest else "",
                "best_duckdb_joules": f"{lowest[3]:.6f}" if lowest else "",
                "mssql_joules": "",
                "energy_reduction_x": "",
                "all_alternatives_tested": len(all_results),
                "status": "FAIL",
            })
            print(f"  op {op_id:02d}: FAIL  ({len(all_results)} alternatives tested)")
    
    # Write CSV
    fieldnames = ["op_id", "best_schema", "best_rewrite", "best_duckdb_joules",
                  "mssql_joules", "energy_reduction_x", "all_alternatives_tested", "status"]
    with open(OUT_CSV, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in results:
            w.writerow(r)
    
    print(f"\n{'='*80}")
    print(f"RESULT: {pass_count}/50 ops have at least one PASS configuration")
    print(f"Search results: {OUT_CSV}")
    
    # Compute total energy
    total_duck = sum(float(r["best_duckdb_joules"]) for r in results if r["status"] == "PASS")
    total_mssql = sum(float(r["mssql_joules"]) for r in results if r["mssql_joules"])
    print(f"\nTotal DuckDB energy (optimal): {total_duck:.4f} J")
    print(f"Total MSSQL energy:            {total_mssql:.4f} J")
    if total_duck > 0 and total_mssql > 0:
        print(f"Overall energy reduction:      {total_mssql/total_duck:.1f}x")
    
    # Find optimal schema distribution
    schema_counts = {"A": 0, "B": 0, "C": 0}
    for r in results:
        if r["status"] == "PASS":
            schema_counts[r["best_schema"]] = schema_counts.get(r["best_schema"], 0) + 1
    print(f"\nOptimal schema distribution: A={schema_counts['A']}, B={schema_counts['B']}, C={schema_counts['C']}")


if __name__ == "__main__":
    main()
