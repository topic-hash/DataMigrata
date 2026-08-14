//! Create views and macros in DuckDB (v1 — TIMESTAMP).
//!
//! Direct port of `scripts/build_duckdb_views.py`.
//!
//! Creates 9 views + 1 table macro in DuckDB (baseline variant A).

use std::path::Path;

use super::super::common::duckdb_conn::{execute, open_read_write};

/// All views to drop before creating.
pub const VIEWS_TO_DROP: &[&str] = &[
    "Sales.vw_NormalizedQuarterlySales",
    "Sales.vw_EmployeeQuarterlySales",
    "Sales.vw_AllTransactions",
    "Sales.vw_ProductSummary",
    "HR.vw_ActiveEmployees",
    "Sales.vw_TransactionSummary",
    "HR.vw_ManagerHierarchy",
    "Sales.vw_MultiDimensionalSales",
    "Sales.vw_RunningTotalsAndRanks",
];

/// All view DDL statements in creation order.
const VIEW_DDLS: &[&str] = &[
    DDL_VW_PRODUCT_SUMMARY,
    DDL_VW_ALL_TRANSACTIONS,
    DDL_VW_ACTIVE_EMPLOYEES,
    DDL_VW_TRANSACTION_SUMMARY,
    DDL_FN_GET_EMPLOYEE_SALES,
    DDL_VW_EMPLOYEE_QUARTERLY_SALES,
    DDL_VW_NORMALIZED_QUARTERLY_SALES,
    DDL_VW_MANAGER_HIERARCHY,
    DDL_VW_MULTI_DIMENSIONAL_SALES,
    DDL_VW_RUNNING_TOTALS_AND_RANKS,
];

/// Create all views and macros in the DuckDB database.
///
/// Direct port of the top-level script in `build_duckdb_views.py`.
pub fn build(db_path: &Path) -> anyhow::Result<()> {
    let con = open_read_write(db_path)?;

    // Load spatial extension (silently fail if not available)
    let _ = execute(&con, "INSTALL spatial");
    let _ = execute(&con, "LOAD spatial");

    // Drop existing views
    for view in VIEWS_TO_DROP {
        let _ = execute(&con, &format!("DROP VIEW IF EXISTS {}", view));
    }
    let _ = execute(&con, "DROP MACRO IF EXISTS fn_GetEmployeeSales");
    let _ = execute(&con, "DROP MACRO IF EXISTS sp_set_session_context");

    // Create views
    for ddl in VIEW_DDLS {
        execute(&con, ddl)?;
    }

    eprintln!("All views and macros created");
    Ok(())
}

const DDL_VW_PRODUCT_SUMMARY: &str = r#"CREATE VIEW Sales.vw_ProductSummary AS
SELECT
    p.Category,
    COUNT(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    SUM(p.CostPrice) AS TotalCostPrice
FROM Sales.Products AS p
GROUP BY p.Category"#;

const DDL_VW_ALL_TRANSACTIONS: &str = r#"CREATE VIEW Sales.vw_AllTransactions AS
SELECT
    TransactionID, EmployeeID, ProductID, Quantity, UnitPrice,
    DiscountPct, TotalAmount, TransactionDate, Region,
    TransactionDetails, PaymentStatus
FROM Sales.Transactions
UNION ALL
SELECT
    TransactionID,
    NULL::INTEGER AS EmployeeID,
    ProductID,
    NULL::INTEGER AS Quantity,
    NULL::DECIMAL(18,4) AS UnitPrice,
    NULL::DECIMAL(5,4) AS DiscountPct,
    CAST(Amount AS DECIMAL(18,2)) AS TotalAmount,
    CAST(ArchiveDate AS TIMESTAMP) AS TransactionDate,
    NULL::VARCHAR AS Region,
    NULL::VARCHAR AS TransactionDetails,
    NULL::VARCHAR AS PaymentStatus
FROM Archive.OldTransactions"#;

const DDL_VW_ACTIVE_EMPLOYEES: &str = r#"CREATE VIEW HR.vw_ActiveEmployees AS
SELECT
    EmployeeID, FullName, Email, Department, JobTitle,
    Salary, HireDate, ManagerID
FROM HR.Employees
WHERE TerminationDate IS NULL"#;

const DDL_VW_TRANSACTION_SUMMARY: &str = r#"CREATE VIEW Sales.vw_TransactionSummary AS
SELECT
    t.TransactionDate,
    COUNT(*) AS TransactionCount,
    SUM(t.TotalAmount) AS DailyTotal,
    AVG(t.TotalAmount) AS AvgTransaction,
    COUNT(DISTINCT t.EmployeeID) AS ActiveEmployees
FROM Sales.Transactions AS t
GROUP BY t.TransactionDate"#;

const DDL_FN_GET_EMPLOYEE_SALES: &str = r#"CREATE MACRO Sales.fn_GetEmployeeSales(employee_id, start_date, end_date) AS TABLE
SELECT
    t.TransactionID, t.TransactionDate, t.ProductID, t.Quantity,
    t.UnitPrice, t.DiscountPct, t.TotalAmount, t.PaymentStatus
FROM Sales.Transactions AS t
WHERE t.EmployeeID = employee_id
  AND t.TransactionDate >= start_date
  AND t.TransactionDate <= end_date"#;

const DDL_VW_EMPLOYEE_QUARTERLY_SALES: &str = r#"CREATE VIEW Sales.vw_EmployeeQuarterlySales AS
SELECT
    EmployeeID, FullName, SaleYear,
    SUM(CASE WHEN Quarter = 'Q1' THEN Amount ELSE NULL END) AS Q1,
    SUM(CASE WHEN Quarter = 'Q2' THEN Amount ELSE NULL END) AS Q2,
    SUM(CASE WHEN Quarter = 'Q3' THEN Amount ELSE NULL END) AS Q3,
    SUM(CASE WHEN Quarter = 'Q4' THEN Amount ELSE NULL END) AS Q4
FROM (
    SELECT
        e.EmployeeID, e.FullName,
        EXTRACT(YEAR FROM t.TransactionDate) AS SaleYear,
        CASE
            WHEN EXTRACT(MONTH FROM t.TransactionDate) <= 3 THEN 'Q1'
            WHEN EXTRACT(MONTH FROM t.TransactionDate) <= 6 THEN 'Q2'
            WHEN EXTRACT(MONTH FROM t.TransactionDate) <= 9 THEN 'Q3'
            ELSE 'Q4'
        END AS Quarter,
        t.TotalAmount AS Amount
    FROM HR.Employees AS e
    INNER JOIN Sales.Transactions AS t ON e.EmployeeID = t.EmployeeID
) AS SourceTable
GROUP BY EmployeeID, FullName, SaleYear"#;

const DDL_VW_NORMALIZED_QUARTERLY_SALES: &str = r#"CREATE VIEW Sales.vw_NormalizedQuarterlySales AS
SELECT EmployeeID, FullName, SaleYear, 'Q1' AS Quarter, Q1 AS Amount
FROM Sales.vw_EmployeeQuarterlySales WHERE Q1 IS NOT NULL
UNION ALL
SELECT EmployeeID, FullName, SaleYear, 'Q2' AS Quarter, Q2 AS Amount
FROM Sales.vw_EmployeeQuarterlySales WHERE Q2 IS NOT NULL
UNION ALL
SELECT EmployeeID, FullName, SaleYear, 'Q3' AS Quarter, Q3 AS Amount
FROM Sales.vw_EmployeeQuarterlySales WHERE Q3 IS NOT NULL
UNION ALL
SELECT EmployeeID, FullName, SaleYear, 'Q4' AS Quarter, Q4 AS Amount
FROM Sales.vw_EmployeeQuarterlySales WHERE Q4 IS NOT NULL"#;

const DDL_VW_MANAGER_HIERARCHY: &str = r#"CREATE VIEW HR.vw_ManagerHierarchy AS
WITH RECURSIVE Hierarchy AS (
    SELECT EmployeeID, ManagerID, FullName, CAST(0 AS INTEGER) AS Level
    FROM HR.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FullName, h.Level + 1 AS Level
    FROM HR.Employees AS e
    INNER JOIN Hierarchy AS h ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10
)
SELECT h.ManagerID, h.EmployeeID, h.FullName, h.Level FROM Hierarchy AS h"#;

const DDL_VW_MULTI_DIMENSIONAL_SALES: &str = r#"CREATE VIEW Sales.vw_MultiDimensionalSales AS
SELECT
    e.Department AS Department,
    e.FullName AS Employee,
    CASE WHEN GROUPING(e.Department) = 1 AND GROUPING(e.FullName) = 1 THEN 'Grand Total'
         WHEN GROUPING(e.Department) = 1 THEN 'Dept Subtotal'
         WHEN GROUPING(e.FullName) = 1 THEN 'Employee Subtotal'
         ELSE 'Detail'
    END AS GroupingLevel,
    COUNT(*) AS TransactionCount,
    SUM(t.TotalAmount) AS TotalSales,
    AVG(t.TotalAmount) AS AvgSales
FROM HR.Employees e
JOIN Sales.Transactions t ON e.EmployeeID = t.EmployeeID
GROUP BY GROUPING SETS ((e.Department, e.FullName), (e.Department), ())"#;

const DDL_VW_RUNNING_TOTALS_AND_RANKS: &str = r#"CREATE VIEW Sales.vw_RunningTotalsAndRanks AS
SELECT
    e.FullName,
    t.TransactionDate,
    t.TotalAmount,
    SUM(t.TotalAmount) OVER (
        PARTITION BY e.FullName
        ORDER BY t.TransactionDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RunningTotal,
    RANK() OVER (
        PARTITION BY e.FullName
        ORDER BY t.TotalAmount DESC
    ) AS SalesRank,
    LAG(t.TotalAmount, 1) OVER (
        PARTITION BY e.FullName
        ORDER BY t.TransactionDate
    ) AS PrevAmount,
    LEAD(t.TotalAmount, 1) OVER (
        PARTITION BY e.FullName
        ORDER BY t.TransactionDate
    ) AS NextAmount
FROM HR.Employees e
JOIN Sales.Transactions t ON e.EmployeeID = t.EmployeeID"#;
