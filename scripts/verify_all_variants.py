#!/usr/bin/env python3
"""
Run verify_ops.py logic against each schema-variant DuckDB database and
write verification_log_{a,b,c}.csv in best_config/.

Reuses the verify_ops module by overriding its DB_PATH and LOG_PATH.
"""
import sys, os, csv
sys.path.insert(0, "/home/z/my-project/scripts")
import verify_ops as vo

VARIANTS = [
    ("a_baseline",   "/home/z/my-project/duckdb_migrated/analytics_a.duckdb",
                     "/home/z/my-project/best_config/verification_log_a_baseline.csv"),
    ("b_columnar",   "/home/z/my-project/duckdb_migrated/analytics_b.duckdb",
                     "/home/z/my-project/best_config/verification_log_b_columnar.csv"),
    ("c_precomputed", "/home/z/my-project/duckdb_migrated/analytics_c.duckdb",
                     "/home/z/my-project/best_config/verification_log_c_precomputed.csv"),
]


def run_variant(label, db_path, log_path):
    print(f"\n=== Variant {label} ===  db={db_path}")
    vo.DB_PATH = db_path
    vo.LOG_PATH = log_path
    # Re-run main() — it will pick up the overridden paths via module globals.
    vo.main()


def main():
    for label, db, log in VARIANTS:
        run_variant(label, db, log)


if __name__ == "__main__":
    main()
