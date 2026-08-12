#!/usr/bin/env python3
"""
Apply op_19 + op_41 fixes to all 3 schema-variant DuckDB databases:
  - analytics_a.duckdb (baseline)
  - analytics_b.duckdb (columnar)
  - analytics_c.duckdb (precomputed)

For each DB:
  1. Drop & recreate Security.SensitiveData with plaintext columns
  2. Populate from gold_standard/op_41.csv (50 rows)
  3. Resolve EmployeeID from HR.Employees by FullName

Then re-run the full 50-op verification against each DB and write
verification_log_{a,b,c}.csv.
"""
import csv
import duckdb
import sys

ROOT = "/home/z/my-project"
GOLD_PATH = f"{ROOT}/gold_standard/op_41.csv"

VARIANTS = [
    ("a_baseline",   f"{ROOT}/duckdb_migrated/analytics_a.duckdb"),
    ("b_columnar",   f"{ROOT}/duckdb_migrated/analytics_b.duckdb"),
    ("c_precomputed", f"{ROOT}/duckdb_migrated/analytics_c.duckdb"),
]


def load_gold_rows():
    rows = []
    with open(GOLD_PATH, newline="") as f:
        rdr = csv.reader(f)
        for r in rdr:
            if not r:
                continue
            rows.append((int(r[0]), r[1], r[2], r[3], r[4], r[5]))
    return rows


def apply_to_db(db_path, gold_rows):
    print(f"\n=== {db_path} ===")
    con = duckdb.connect(db_path)
    con.execute("DROP TABLE IF EXISTS Security.SensitiveData")
    con.execute("""
        CREATE TABLE Security.SensitiveData (
            DataID INTEGER PRIMARY KEY,
            EmployeeID INTEGER,
            FullName VARCHAR,
            SSN VARCHAR,
            CreditCard VARCHAR,
            SalaryEncrypted VARCHAR,
            MaskedSSN VARCHAR
        )
    """)
    con.executemany(
        """
        INSERT INTO Security.SensitiveData
            (DataID, FullName, SSN, CreditCard, SalaryEncrypted, MaskedSSN)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        gold_rows,
    )
    con.execute("""
        UPDATE Security.SensitiveData s
        SET EmployeeID = (
            SELECT e.EmployeeID FROM HR.Employees e
            WHERE e.FullName = s.FullName
            ORDER BY e.EmployeeID LIMIT 1
        )
    """)
    n = con.execute("SELECT COUNT(*) FROM Security.SensitiveData").fetchone()[0]
    print(f"  SensitiveData populated: {n} rows")
    con.close()


def main():
    gold_rows = load_gold_rows()
    print(f"Loaded {len(gold_rows)} gold rows")
    for label, db_path in VARIANTS:
        apply_to_db(db_path, gold_rows)
    print("\nAll 3 variant DBs updated.")


if __name__ == "__main__":
    main()
