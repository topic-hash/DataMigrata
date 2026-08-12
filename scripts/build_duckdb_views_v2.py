#!/usr/bin/env python3
"""
Build DuckDB views with VARCHAR timestamp handling.
datetime2 columns are stored as VARCHAR, so we CAST them when needed.
"""
import duckdb
import os

DB_PATH = '/home/z/my-project/duckdb_migrated/analytics.duckdb'

con = duckdb.connect(DB_PATH)

try:
    con.execute("INSTALL spatial")
    con.execute("LOAD spatial")
except:
    pass

# Drop existing views
for view in ['Sales.vw_NormalizedQuarterlySales', 'Sales.vw_EmployeeQuarterlySales',
             'Sales.vw_AllTransactions', 'Sales.vw_ProductSummary',
             'HR.vw_ActiveEmployees', 'Sales.vw_TransactionSummary',
             'HR.vw_ManagerHierarchy', 'Sales.vw_MultiDimensionalSales',
             'Sales.vw_RunningTotalsAndRanks']:
    try:
        con.execute(f"DROP VIEW IF EXISTS {view}")
    except:
        pass

for fn in ['fn_GetEmployeeSales']:
    try:
        con.execute(f"DROP MACRO IF EXISTS Sales.{fn}")
    except:
        pass

# 1. Sales.vw_ProductSummary
con.execute("""
CREATE VIEW Sales.vw_ProductSummary AS
SELECT
    p.Category,
    COUNT(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    SUM(p.CostPrice) AS TotalCostPrice
FROM Sales.Products AS p
GROUP BY p.Category
""")

# 2. Sales.vw_AllTransactions
con.execute("""
CREATE VIEW Sales.vw_AllTransactions AS
SELECT
    TransactionID,
    EmployeeID,
    ProductID,
    Quantity,
    UnitPrice,
    DiscountPct,
    TotalAmount,
    TransactionDate,
    Region,
    TransactionDetails,
    PaymentStatus
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
    CAST(ArchiveDate AS VARCHAR) AS TransactionDate,
    NULL::VARCHAR AS Region,
    NULL::VARCHAR AS TransactionDetails,
    NULL::VARCHAR AS PaymentStatus
FROM Archive.OldTransactions
""")

# 3. HR.vw_ActiveEmployees
con.execute("""
CREATE VIEW HR.vw_ActiveEmployees AS
SELECT
    EmployeeID,
    FullName,
    Email,
    Department,
    JobTitle,
    Salary,
    HireDate,
    ManagerID
FROM HR.Employees
WHERE TerminationDate IS NULL
""")

# 4. Sales.vw_TransactionSummary
con.execute("""
CREATE VIEW Sales.vw_TransactionSummary AS
SELECT
    t.TransactionDate,
    COUNT(*) AS TransactionCount,
    SUM(t.TotalAmount) AS DailyTotal,
    AVG(t.TotalAmount) AS AvgTransaction,
    COUNT(DISTINCT t.EmployeeID) AS ActiveEmployees
FROM Sales.Transactions AS t
GROUP BY t.TransactionDate
""")

# 5. Sales.fn_GetEmployeeSales
con.execute("""
CREATE MACRO Sales.fn_GetEmployeeSales(employee_id, start_date, end_date) AS TABLE
SELECT
    t.TransactionID,
    t.TransactionDate,
    t.ProductID,
    t.Quantity,
    t.UnitPrice,
    t.DiscountPct,
    t.TotalAmount,
    t.PaymentStatus
FROM Sales.Transactions AS t
WHERE t.EmployeeID = employee_id
  AND CAST(t.TransactionDate AS TIMESTAMP) >= start_date
  AND CAST(t.TransactionDate AS TIMESTAMP) <= end_date
""")

# 6. Sales.vw_EmployeeQuarterlySales (PIVOT) - CAST TransactionDate for EXTRACT
con.execute("""
CREATE VIEW Sales.vw_EmployeeQuarterlySales AS
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    SUM(CASE WHEN Quarter = 'Q1' THEN Amount ELSE NULL END) AS Q1,
    SUM(CASE WHEN Quarter = 'Q2' THEN Amount ELSE NULL END) AS Q2,
    SUM(CASE WHEN Quarter = 'Q3' THEN Amount ELSE NULL END) AS Q3,
    SUM(CASE WHEN Quarter = 'Q4' THEN Amount ELSE NULL END) AS Q4
FROM (
    SELECT
        e.EmployeeID,
        e.FullName,
        EXTRACT(YEAR FROM CAST(t.TransactionDate AS TIMESTAMP)) AS SaleYear,
        CASE
            WHEN EXTRACT(MONTH FROM CAST(t.TransactionDate AS TIMESTAMP)) <= 3  THEN 'Q1'
            WHEN EXTRACT(MONTH FROM CAST(t.TransactionDate AS TIMESTAMP)) <= 6  THEN 'Q2'
            WHEN EXTRACT(MONTH FROM CAST(t.TransactionDate AS TIMESTAMP)) <= 9  THEN 'Q3'
            ELSE 'Q4'
        END AS Quarter,
        t.TotalAmount AS Amount
    FROM HR.Employees AS e
    INNER JOIN Sales.Transactions AS t
        ON e.EmployeeID = t.EmployeeID
) AS SourceTable
GROUP BY EmployeeID, FullName, SaleYear
""")

# 7. Sales.vw_NormalizedQuarterlySales
con.execute("""
CREATE VIEW Sales.vw_NormalizedQuarterlySales AS
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
FROM Sales.vw_EmployeeQuarterlySales WHERE Q4 IS NOT NULL
""")

# 8. HR.vw_ManagerHierarchy
con.execute("""
CREATE VIEW HR.vw_ManagerHierarchy AS
WITH RECURSIVE Hierarchy AS (
    SELECT EmployeeID, ManagerID, FullName, CAST(0 AS INTEGER) AS Level
    FROM HR.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FullName, h.Level + 1 AS Level
    FROM HR.Employees AS e
    INNER JOIN Hierarchy AS h ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10
)
SELECT h.ManagerID, h.EmployeeID, h.FullName, h.Level
FROM Hierarchy AS h
""")

# 9. Sales.vw_MultiDimensionalSales
con.execute("""
CREATE VIEW Sales.vw_MultiDimensionalSales AS
SELECT
    e.Department AS Department,
    e.FullName   AS Employee,
    CASE WHEN GROUPING(e.Department) = 1 AND GROUPING(e.FullName) = 1 THEN 'Grand Total'
         WHEN GROUPING(e.Department) = 1                          THEN 'Dept Subtotal'
         WHEN GROUPING(e.FullName)   = 1                          THEN 'Employee Subtotal'
         ELSE 'Detail'
    END AS GroupingLevel,
    COUNT(*)           AS TransactionCount,
    SUM(t.TotalAmount) AS TotalSales,
    AVG(t.TotalAmount) AS AvgSales
FROM HR.Employees e
JOIN Sales.Transactions t ON e.EmployeeID = t.EmployeeID
GROUP BY GROUPING SETS (
    (e.Department, e.FullName),
    (e.Department),
    ()
)
""")

# 10. Sales.vw_RunningTotalsAndRanks
con.execute("""
CREATE VIEW Sales.vw_RunningTotalsAndRanks AS
SELECT
    e.FullName,
    t.TransactionDate,
    t.TotalAmount,
    SUM(t.TotalAmount) OVER (
        PARTITION BY e.FullName
        ORDER BY CAST(t.TransactionDate AS TIMESTAMP)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RunningTotal,
    RANK() OVER (
        PARTITION BY e.FullName
        ORDER BY t.TotalAmount DESC
    ) AS SalesRank,
    LAG(t.TotalAmount, 1) OVER (
        PARTITION BY e.FullName
        ORDER BY CAST(t.TransactionDate AS TIMESTAMP)
    ) AS PrevAmount,
    LEAD(t.TotalAmount, 1) OVER (
        PARTITION BY e.FullName
        ORDER BY CAST(t.TransactionDate AS TIMESTAMP)
    ) AS NextAmount
FROM HR.Employees e
JOIN Sales.Transactions t ON e.EmployeeID = t.EmployeeID
""")

print("All views and macros created")
con.close()
