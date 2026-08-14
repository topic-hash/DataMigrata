//! Build 3 schema variant DuckDB databases (A=baseline, B=LOB side-tables, C=precomputed).
//!
//! Direct port of `scripts/build_schema_variants.py`.

use std::path::Path;

use super::super::common::duckdb_conn::{execute, open_read_write};

/// Build all 3 schema variants from the source database.
///
/// Direct port of the `__main__` block in `build_schema_variants.py`.
pub fn build_all(root: &str) -> anyhow::Result<()> {
    let src_db = Path::new(root).join("duckdb_migrated/analytics.duckdb");
    let var_a = Path::new(root).join("duckdb_migrated/analytics_a.duckdb");
    let var_b = Path::new(root).join("duckdb_migrated/analytics_b.duckdb");
    let var_c = Path::new(root).join("duckdb_migrated/analytics_c.duckdb");

    build_variant_a(&src_db, &var_a)?;
    build_variant_b(&src_db, &var_b)?;
    build_variant_c(&src_db, &var_c)?;

    eprintln!("\nAll 3 schema variants built.");
    Ok(())
}

/// Variant A: baseline copy.
fn build_variant_a(src: &Path, dst: &Path) -> anyhow::Result<()> {
    eprintln!("Building variant A (baseline)...");
    std::fs::copy(src, dst)?;
    eprintln!("  Copied {} → {}", src.display(), dst.display());
    Ok(())
}

/// Variant B: LOB side-tables.
fn build_variant_b(src: &Path, dst: &Path) -> anyhow::Result<()> {
    eprintln!("Building variant B (columnar — LOB side-tables)...");
    std::fs::copy(src, dst)?;
    let con = open_read_write(dst)?;

    // Create LOB side-tables
    execute(&con, "CREATE TABLE IF NOT EXISTS hr_employees_lob (row_id INTEGER PRIMARY KEY, EmployeeData TEXT)")?;
    execute(&con, "CREATE TABLE IF NOT EXISTS sales_transactions_lob (row_id INTEGER PRIMARY KEY, Region TEXT)")?;

    // Move LOB data
    execute(&con, "INSERT INTO hr_employees_lob (row_id, EmployeeData) SELECT EmployeeID, EmployeeData FROM HR.Employees WHERE EmployeeData IS NOT NULL")?;
    execute(&con, "INSERT INTO sales_transactions_lob (row_id, Region) SELECT TransactionID, Region FROM Sales.Transactions WHERE Region IS NOT NULL")?;

    // Add reference columns
    execute(&con, "ALTER TABLE HR.Employees ADD COLUMN IF NOT EXISTS EmployeeData_id INTEGER")?;
    execute(&con, "ALTER TABLE Sales.Transactions ADD COLUMN IF NOT EXISTS Region_id INTEGER")?;

    // Populate reference IDs
    execute(&con, "UPDATE HR.Employees SET EmployeeData_id = EmployeeID WHERE EmployeeData IS NOT NULL")?;
    execute(&con, "UPDATE Sales.Transactions SET Region_id = TransactionID WHERE Region IS NOT NULL")?;

    eprintln!("  Variant B built");
    Ok(())
}

/// Variant C: precomputed materialized paths + bbox.
fn build_variant_c(src: &Path, dst: &Path) -> anyhow::Result<()> {
    eprintln!("Building variant C (precomputed)...");
    std::fs::copy(src, dst)?;
    let con = open_read_write(dst)?;

    // Add columns
    execute(&con, "ALTER TABLE HR.Employees ADD COLUMN IF NOT EXISTS materialized_path TEXT")?;
    execute(&con, "ALTER TABLE HR.Employees ADD COLUMN IF NOT EXISTS depth INTEGER")?;
    execute(&con, "ALTER TABLE Sales.Transactions ADD COLUMN IF NOT EXISTS bbox_lat DOUBLE")?;
    execute(&con, "ALTER TABLE Sales.Transactions ADD COLUMN IF NOT EXISTS bbox_lon DOUBLE")?;

    // Populate materialized_path via recursive CTE
    execute(&con, "
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
    ")?;

    // Populate bbox_lat / bbox_lon from Region WKT
    execute(&con, "
        UPDATE Sales.Transactions SET
            bbox_lon = CAST(regexp_extract(Region, 'POINT \\(-?[0-9.]+ ', 1) AS DOUBLE),
            bbox_lat = CAST(regexp_extract(Region, 'POINT \\(-?[0-9.]+ (-?[0-9.]+)\\)', 1) AS DOUBLE)
        WHERE Region IS NOT NULL AND Region LIKE 'POINT%'
    ")?;

    // Create distance table
    execute(&con, "CREATE TABLE IF NOT EXISTS sales_transaction_distances (FromTransactionID BIGINT, ToTransactionID BIGINT, DistanceKm DOUBLE, PRIMARY KEY (FromTransactionID, ToTransactionID))")?;

    eprintln!("  Variant C built");
    Ok(())
}
