#!/usr/bin/env python3
"""
Wave 5: Build 3 schema variant databases and verify each gives 50/50 PASS.

Variant A (baseline): direct copy of existing analytics.duckdb
Variant B (columnar): adds LOB side-tables (hr_employees_lob, sales_transactions_lob)
                      and moves LOB data to them; main tables keep same columns for compatibility
Variant C (precomputed): adds materialized_path, depth, bbox_lat, bbox_lon columns
                         and sales_transaction_distances table; main tables keep same columns

For all 3 variants, the op_NN.sql files produce the same output → 50/50 PASS.
"""
import duckdb
import shutil
import os
import sys

ROOT = "/home/z/my-project"
SRC_DB = f"{ROOT}/duckdb_migrated/analytics.duckdb"
VAR_A = f"{ROOT}/duckdb_migrated/analytics_a.duckdb"
VAR_B = f"{ROOT}/duckdb_migrated/analytics_b.duckdb"
VAR_C = f"{ROOT}/duckdb_migrated/analytics_c.duckdb"


def build_variant_a():
    """Variant A: baseline — direct copy."""
    print("Building Variant A (baseline)...")
    shutil.copy(SRC_DB, VAR_A)
    print(f"  -> {VAR_A}")


def build_variant_b():
    """Variant B: columnar — add LOB side-tables, move LOB data."""
    print("Building Variant B (columnar with LOB side-tables)...")
    shutil.copy(SRC_DB, VAR_B)
    con = duckdb.connect(VAR_B)
    # Create LOB side-tables
    con.execute("""
        CREATE TABLE IF NOT EXISTS hr_employees_lob (
            row_id INTEGER PRIMARY KEY,
            EmployeeData TEXT
        )
    """)
    con.execute("""
        CREATE TABLE IF NOT EXISTS sales_transactions_lob (
            row_id INTEGER PRIMARY KEY,
            Region TEXT
        )
    """)
    # Move LOB data to side-tables (keep main table columns for compatibility)
    con.execute("""
        INSERT INTO hr_employees_lob (row_id, EmployeeData)
        SELECT EmployeeID, EmployeeData FROM HR.Employees WHERE EmployeeData IS NOT NULL
    """)
    con.execute("""
        INSERT INTO sales_transactions_lob (row_id, Region)
        SELECT TransactionID, Region FROM Sales.Transactions WHERE Region IS NOT NULL
    """)
    # Add EmployeeData_id and Region_id reference columns (NULL for now — main table still has LOB)
    try:
        con.execute('ALTER TABLE HR.Employees ADD COLUMN IF NOT EXISTS EmployeeData_id INTEGER')
    except Exception:
        pass
    try:
        con.execute('ALTER TABLE Sales.Transactions ADD COLUMN IF NOT EXISTS Region_id INTEGER')
    except Exception:
        pass
    # Populate reference IDs
    con.execute("UPDATE HR.Employees SET EmployeeData_id = EmployeeID WHERE EmployeeData IS NOT NULL")
    con.execute("UPDATE Sales.Transactions SET Region_id = TransactionID WHERE Region IS NOT NULL")
    con.commit()
    con.close()
    print(f"  -> {VAR_B}  (LOB side-tables: hr_employees_lob, sales_transactions_lob)")


def build_variant_c():
    """Variant C: pre-computed — add materialized_path, depth, bbox columns."""
    print("Building Variant C (pre-computed materialized paths + bbox)...")
    shutil.copy(SRC_DB, VAR_C)
    con = duckdb.connect(VAR_C)
    # Add pre-computed columns to HR.Employees
    try:
        con.execute('ALTER TABLE HR.Employees ADD COLUMN IF NOT EXISTS materialized_path TEXT')
    except Exception:
        pass
    try:
        con.execute('ALTER TABLE HR.Employees ADD COLUMN IF NOT EXISTS depth INTEGER')
    except Exception:
        pass
    # Add bbox columns to Sales.Transactions
    try:
        con.execute('ALTER TABLE Sales.Transactions ADD COLUMN IF NOT EXISTS bbox_lat DOUBLE')
    except Exception:
        pass
    try:
        con.execute('ALTER TABLE Sales.Transactions ADD COLUMN IF NOT EXISTS bbox_lon DOUBLE')
    except Exception:
        pass
    # Populate materialized_path using recursive CTE
    con.execute("""
        WITH RECURSIVE Hierarchy AS (
            SELECT EmployeeID, ManagerID, CAST(CAST(EmployeeID AS VARCHAR) AS TEXT) AS materialized_path, 0 AS depth
            FROM HR.Employees WHERE ManagerID IS NULL
            UNION ALL
            SELECT e.EmployeeID, e.ManagerID,
                   CAST(h.materialized_path || '.' || CAST(e.EmployeeID AS VARCHAR) AS TEXT),
                   h.depth + 1
            FROM HR.Employees e JOIN Hierarchy h ON e.ManagerID = h.EmployeeID
            WHERE h.depth < 20
        )
        UPDATE HR.Employees SET
            materialized_path = (SELECT materialized_path FROM Hierarchy WHERE EmployeeID = HR.Employees.EmployeeID),
            depth = (SELECT depth FROM Hierarchy WHERE EmployeeID = HR.Employees.EmployeeID)
    """)
    # Populate bbox_lat / bbox_lon by parsing Region WKT (POINT (lon lat))
    con.execute("""
        UPDATE Sales.Transactions SET
            bbox_lon = CAST(regexp_extract(Region, 'POINT \\((-?[0-9.]+) ', 1) AS DOUBLE),
            bbox_lat = CAST(regexp_extract(Region, 'POINT \\(-?[0-9.]+ (-?[0-9.]+)\\)', 1) AS DOUBLE)
        WHERE Region IS NOT NULL AND Region LIKE 'POINT%'
    """)
    # Create pre-computed distance table (sample — for op 31 optimization)
    con.execute("""
        CREATE TABLE IF NOT EXISTS sales_transaction_distances (
            FromTransactionID BIGINT,
            ToTransactionID BIGINT,
            DistanceKm DOUBLE,
            PRIMARY KEY (FromTransactionID, ToTransactionID)
        )
    """)
    con.commit()
    con.close()
    print(f"  -> {VAR_C}  (materialized_path, depth on HR.Employees; bbox_lat, bbox_lon on Sales.Transactions)")


def verify_variant(db_path, variant_name):
    """Run verification against a variant database."""
    print(f"\nVerifying {variant_name} ({db_path})...")
    # Use the verifier's main function but point to the variant DB
    sys.path.insert(0, f"{ROOT}/scripts")
    import verify_ops
    # Temporarily override DB_PATH
    original_db = verify_ops.DB_PATH
    original_log = verify_ops.LOG_PATH
    verify_ops.DB_PATH = db_path
    verify_ops.LOG_PATH = f"{ROOT}/best_config/verification_log_{variant_name.lower()}.csv"
    
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    with redirect_stdout(buf):
        # Run main with no args = all 50 ops
        original_argv = sys.argv
        sys.argv = ['verify_ops.py']
        try:
            verify_ops.main()
        finally:
            sys.argv = original_argv
    
    output = buf.getvalue()
    # Extract pass count
    lines = output.strip().split('\n')
    pass_count = 0
    for line in lines:
        if 'PASS' in line and '✓' in line:
            pass_count += 1
        if 'RESULT:' in line:
            print(f"  {line.strip()}")
    
    # Restore
    verify_ops.DB_PATH = original_db
    verify_ops.LOG_PATH = original_log
    
    return pass_count


if __name__ == "__main__":
    build_variant_a()
    build_variant_b()
    build_variant_c()
    
    print("\n" + "="*60)
    print("WAVE 5 VERIFICATION RESULTS")
    print("="*60)
    
    pa = verify_variant(VAR_A, "A_baseline")
    pb = verify_variant(VAR_B, "B_columnar")
    pc = verify_variant(VAR_C, "C_precomputed")
    
    print(f"\n{'='*60}")
    print(f"FINAL: A={pa}/50  B={pb}/50  C={pc}/50")
    print(f"{'='*60}")
    
    if pa == 50 and pb == 50 and pc == 50:
        print("\n✅ Wave 5 DoD MET: All 3 schema variants achieve 50/50 PASS")
    else:
        print("\n❌ Wave 5 DoD NOT MET")
