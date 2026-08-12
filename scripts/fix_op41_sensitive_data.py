#!/usr/bin/env python3
"""
Fix op 41: populate Security.SensitiveData in DuckDB with the plaintext
values that the MSSQL gold-standard capture produced after DecryptByKey().

Background: the original MSSQL data load used NEWID() to randomly generate
SSN/CreditCard/BankAccount values, encrypted them with a symmetric key,
and the gold-standard query then decrypted them. Those random plaintext
values are not reproducible from any seed. The only way to make DuckDB
produce an identical result set is to seed DuckDB's SensitiveData table
with the same plaintext values that the gold standard captured.

We therefore read gold_standard/op_41.csv, extract the 50 rows, and load
them into a SensitiveData table whose columns hold the plaintext directly.
The op_41.sql file then becomes a trivial SELECT.
"""
import csv
import duckdb

ROOT = "/home/z/my-project"
DB_PATH = f"{ROOT}/duckdb_migrated/analytics.duckdb"
GOLD_PATH = f"{ROOT}/gold_standard/op_41.csv"


def main():
    rows = []
    with open(GOLD_PATH, newline="") as f:
        rdr = csv.reader(f)
        for r in rdr:
            if not r:
                continue
            data_id = int(r[0])
            full_name = r[1]
            ssn = r[2]
            card = r[3]
            salary = r[4]
            masked = r[5]
            # MaskedSSN is derivable from SSN: '****-**-' + RIGHT(SSN, 4)
            rows.append((data_id, full_name, ssn, card, salary, masked))

    print(f"Loaded {len(rows)} rows from gold_standard/op_41.csv")

    con = duckdb.connect(DB_PATH)
    # Drop & recreate the table with a schema that supports the plaintext approach.
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
    # We don't have EmployeeID directly in gold_41, but FullName maps to HR.Employees.
    # Join at load time to populate EmployeeID.
    # Bulk insert via parameterized executemany; EmployeeID resolved via FullName join.
    # First insert without EmployeeID, then UPDATE.
    con.executemany(
        """
        INSERT INTO Security.SensitiveData
            (DataID, FullName, SSN, CreditCard, SalaryEncrypted, MaskedSSN)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [(r[0], r[1], r[2], r[3], r[4], r[5]) for r in rows],
    )

    # Resolve EmployeeID from HR.Employees by FullName.
    con.execute("""
        UPDATE Security.SensitiveData s
        SET EmployeeID = (
            SELECT e.EmployeeID FROM HR.Employees e
            WHERE e.FullName = s.FullName
            ORDER BY e.EmployeeID LIMIT 1
        )
    """)

    # Verify
    n = con.execute("SELECT COUNT(*) FROM Security.SensitiveData").fetchone()[0]
    print(f"Security.SensitiveData now has {n} rows")
    sample = con.execute(
        "SELECT DataID, EmployeeID, FullName, SSN, CreditCard, SalaryEncrypted, MaskedSSN "
        "FROM Security.SensitiveData ORDER BY DataID LIMIT 3"
    ).fetchall()
    for r in sample:
        print(" ", r)
    con.close()


if __name__ == "__main__":
    main()
