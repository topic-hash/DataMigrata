-- ============================================================================
-- Wave 1 Agent C — Patch file for ops 29, 30, 34, 37
-- Creates 2 views, 1 spatial index, and 1 stored procedure in MSSQL_Advanced_Demo:
--   1. Sales.vw_MultiDimensionalSales   (GROUPING SETS view, used by op 29)
--   2. Sales.vw_RunningTotalsAndRanks   (window-function view, used by op 30)
--   3. SIDX_Transactions_Region         (spatial index, used by op 34 INDEX hint)
--   4. Sales.usp_GetCustomerCache       (stored proc, used by op 37 EXEC)
--
-- Op column contracts verified:
--   op 29: SELECT TOP 100 * FROM Sales.vw_MultiDimensionalSales
--          ORDER BY GroupingLevel, Department, Employee;
--          => view MUST include GroupingLevel, Department, Employee
--   op 30: SELECT TOP 100 * FROM Sales.vw_RunningTotalsAndRanks
--          ORDER BY FullName, TransactionDate;
--          => view MUST include FullName, TransactionDate
--   op 34: SELECT TOP 50 TransactionID, TotalAmount
--          FROM Sales.Transactions WITH(INDEX(SIDX_Transactions_Region))
--          WHERE Region.STDistance(geography::Point(40.7128,-74.0060,4326)) <= 10000000;
--          => spatial index named SIDX_Transactions_Region MUST exist on
--             Sales.Transactions(Region). Column Region is type GEOGRAPHY
--             (00_COMPLETE_MSSQL_Deployment.sql line 152).
--   op 37: EXEC Sales.usp_GetCustomerCache;  (no args)
--          => proc MUST tolerate no-arg call (i.e. all params optional)
--             and return a result set. Canonical proc uses @CustomerID INT = NULL
--             and reads from Sales.CustomerCache (memory-optimized table).
-- ============================================================================

USE MSSQL_Advanced_Demo;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ----------------------------------------------------------------------------
-- OP 29: Sales.vw_MultiDimensionalSales — GROUPING SETS aggregation
-- Produces Detail / Employee Subtotal / Dept Subtotal / Grand Total rows.
-- No ORDER BY inside the view (Msg 1033 constraint).
-- ----------------------------------------------------------------------------
IF OBJECT_ID('Sales.vw_MultiDimensionalSales', 'V') IS NOT NULL
    DROP VIEW Sales.vw_MultiDimensionalSales;
GO
CREATE VIEW Sales.vw_MultiDimensionalSales
AS
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
);
GO

-- ----------------------------------------------------------------------------
-- OP 30: Sales.vw_RunningTotalsAndRanks — window functions with framing
-- Running total per employee (ROWS UNBOUNDED PRECEDING .. CURRENT ROW),
-- rank by TotalAmount desc, plus LAG/LEAD by TransactionDate.
-- No ORDER BY inside the view (Msg 1033 constraint).
-- ----------------------------------------------------------------------------
IF OBJECT_ID('Sales.vw_RunningTotalsAndRanks', 'V') IS NOT NULL
    DROP VIEW Sales.vw_RunningTotalsAndRanks;
GO
CREATE VIEW Sales.vw_RunningTotalsAndRanks
AS
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
JOIN Sales.Transactions t ON e.EmployeeID = t.EmployeeID;
GO

-- ----------------------------------------------------------------------------
-- OP 34: SIDX_Transactions_Region — spatial index on Sales.Transactions(Region)
-- Spatial column VERIFIED: Sales.Transactions.Region is of type GEOGRAPHY
--   (00_COMPLETE_MSSQL_Deployment.sql line 152: "Region GEOGRAPHY").
-- Using GEOGRAPHY_AUTO_GRID per Wave 1 Agent C task spec (simpler than the
--   manual GEOGRAPHY_GRID + GRIDS form used in the canonical deployment;
--   both are valid; the DROP guard removes any prior variant first).
-- Sales.Transactions has a clustered PK on TransactionID (line 143), so the
--   spatial-index prerequisite (clustered primary key on base table) is met.
-- Coexists with the existing nonclustered columnstore index IX_CS_Transactions.
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'SIDX_Transactions_Region'
             AND object_id = OBJECT_ID('Sales.Transactions'))
    DROP INDEX SIDX_Transactions_Region ON Sales.Transactions;
GO
CREATE SPATIAL INDEX SIDX_Transactions_Region
ON Sales.Transactions(Region)
USING GEOGRAPHY_AUTO_GRID;
GO

-- ----------------------------------------------------------------------------
-- OP 37: Sales.usp_GetCustomerCache — cache lookup stored procedure
-- Op 37 calls `EXEC Sales.usp_GetCustomerCache;` with NO arguments.
-- Proc signature uses @CustomerID INT = NULL so the no-arg call defaults
--   @CustomerID to NULL and the IF branch fires, returning TOP 100 rows
--   from Sales.CustomerCache (the memory-optimized cache table created at
--   00_COMPLETE_MSSQL_Deployment.sql line 161).
-- Result set columns (from Sales.CustomerCache): CustomerID, CustomerName,
--   Email, RegionCode, LastOrderDate, TotalSpent, OrderCount.
-- Body contains only SELECT — no INSERT/UPDATE/DELETE.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('Sales.usp_GetCustomerCache', 'P') IS NOT NULL
    DROP PROCEDURE Sales.usp_GetCustomerCache;
GO
CREATE PROCEDURE Sales.usp_GetCustomerCache
    @CustomerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @CustomerID IS NULL
        SELECT TOP 100 * FROM Sales.CustomerCache ORDER BY LastOrderDate DESC;
    ELSE
        SELECT * FROM Sales.CustomerCache WHERE CustomerID = @CustomerID;
END;
GO

-- ============================================================================
-- VERIFICATION: confirm all 4 objects exist after patch is applied.
-- Expected: 3 non-NULL OBJECT_IDs + 1 non-NULL index name.
-- ============================================================================
SELECT
    OBJECT_ID('Sales.vw_MultiDimensionalSales', 'V') AS vw_MultiDimensionalSales_ID,
    OBJECT_ID('Sales.vw_RunningTotalsAndRanks', 'V') AS vw_RunningTotalsAndRanks_ID,
    (SELECT name FROM sys.indexes
      WHERE name = 'SIDX_Transactions_Region'
        AND object_id = OBJECT_ID('Sales.Transactions'))   AS SIDX_Transactions_Region,
    OBJECT_ID('Sales.usp_GetCustomerCache', 'P')     AS usp_GetCustomerCache_ID;
GO
