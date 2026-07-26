-- ============================================================================
-- Wave 1 Agent B — Patch file for ops 25-28
-- Creates 1 inline table-valued function and 3 views in MSSQL_Advanced_Demo:
--   1. Sales.fn_GetEmployeeSales           (inline TVF, used by op 25)
--   2. Sales.vw_EmployeeQuarterlySales     (PIVOT view,   used by op 26)
--   3. Sales.vw_NormalizedQuarterlySales   (UNPIVOT view, used by op 27)
--   4. HR.vw_ManagerHierarchy              (recursive CTE view, used by op 28)
--
-- Op column contracts verified:
--   op 25: Sales.fn_GetEmployeeSales(@EmployeeID INT, @StartDate DATE, @EndDate DATE)
--          -> SELECT TOP 50 * ... ORDER BY TransactionDate
--          => function MUST return TransactionDate (plus sales context cols)
--   op 26: SELECT * FROM Sales.vw_EmployeeQuarterlySales ORDER BY EmployeeID
--          => view MUST include EmployeeID (PIVOT cross-tab: EmployeeID, FullName, SaleYear, Q1-Q4)
--   op 27: SELECT * FROM Sales.vw_NormalizedQuarterlySales
--          WHERE Amount IS NOT NULL ORDER BY EmployeeID, Quarter
--          => view MUST include EmployeeID, Quarter, Amount
--   op 28: SELECT * FROM HR.vw_ManagerHierarchy ORDER BY ManagerID, Level
--          => view MUST include ManagerID, Level (no ORDER BY inside view)
-- ============================================================================

USE MSSQL_Advanced_Demo;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- OBJECT 1: Sales.fn_GetEmployeeSales (inline table-valued function)
--   Parameters: @EmployeeID INT, @StartDate DATE, @EndDate DATE
--   Returns per-transaction sales rows for a single employee within a date
--   range. Returns TransactionDate so that op 25's ORDER BY TransactionDate
--   succeeds.
-- ============================================================================
-- Drop any prior version (no type filter so we cover both 'IF' and 'TF').
IF OBJECT_ID('Sales.fn_GetEmployeeSales') IS NOT NULL
    DROP FUNCTION Sales.fn_GetEmployeeSales;
GO
CREATE FUNCTION Sales.fn_GetEmployeeSales (
    @EmployeeID INT,
    @StartDate  DATE,
    @EndDate    DATE
)
RETURNS TABLE
AS
RETURN (
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
    WHERE t.EmployeeID = @EmployeeID
      AND t.TransactionDate >= @StartDate
      AND t.TransactionDate <= @EndDate
);
GO

-- ============================================================================
-- OBJECT 2: Sales.vw_EmployeeQuarterlySales (PIVOT view, cross-tabulation)
--   Produces one row per (EmployeeID, SaleYear) with Q1/Q2/Q3/Q4 columns.
--   Op 26 selects * and orders by EmployeeID.
--   No ORDER BY in the view (constraint + Msg 1033 fix).
-- ============================================================================
IF OBJECT_ID('Sales.vw_EmployeeQuarterlySales', 'V') IS NOT NULL
    DROP VIEW Sales.vw_EmployeeQuarterlySales;
GO
CREATE VIEW Sales.vw_EmployeeQuarterlySales
AS
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    [Q1],
    [Q2],
    [Q3],
    [Q4]
FROM (
    SELECT
        e.EmployeeID,
        e.FullName,
        YEAR(t.TransactionDate) AS SaleYear,
        CASE
            WHEN MONTH(t.TransactionDate) <= 3  THEN 'Q1'
            WHEN MONTH(t.TransactionDate) <= 6  THEN 'Q2'
            WHEN MONTH(t.TransactionDate) <= 9  THEN 'Q3'
            ELSE 'Q4'
        END AS Quarter,
        t.TotalAmount AS Amount
    FROM HR.Employees AS e
    INNER JOIN Sales.Transactions AS t
        ON e.EmployeeID = t.EmployeeID
) AS SourceTable
PIVOT (
    SUM(Amount)
    FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS PivotTable;
GO

-- ============================================================================
-- OBJECT 3: Sales.vw_NormalizedQuarterlySales (UNPIVOT view, normalization)
--   One row per (EmployeeID, Quarter) with an Amount column. Op 27 filters
--   WHERE Amount IS NOT NULL and orders by EmployeeID, Quarter.
--   Depends on Sales.vw_EmployeeQuarterlySales (created above).
--   No ORDER BY in the view.
-- ============================================================================
IF OBJECT_ID('Sales.vw_NormalizedQuarterlySales', 'V') IS NOT NULL
    DROP VIEW Sales.vw_NormalizedQuarterlySales;
GO
CREATE VIEW Sales.vw_NormalizedQuarterlySales
AS
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    Quarter,
    Amount
FROM Sales.vw_EmployeeQuarterlySales
UNPIVOT (
    Amount FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS UnpivotedTable;
GO

-- ============================================================================
-- OBJECT 4: HR.vw_ManagerHierarchy (recursive CTE view)
--   Walks the HR.Employees self-reference via ManagerID up to depth 10.
--   Op 28 selects * and orders by ManagerID, Level.
--   No ORDER BY in the view (Msg 1033 fix from prior run).
-- ============================================================================
IF OBJECT_ID('HR.vw_ManagerHierarchy', 'V') IS NOT NULL
    DROP VIEW HR.vw_ManagerHierarchy;
GO
CREATE VIEW HR.vw_ManagerHierarchy
AS
WITH Hierarchy AS (
    -- Anchor: top-level employees with no manager
    SELECT
        EmployeeID,
        ManagerID,
        FullName,
        CAST(0 AS INT) AS Level
    FROM HR.Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive: each employee's direct reports, capped at depth 10
    SELECT
        e.EmployeeID,
        e.ManagerID,
        e.FullName,
        h.Level + 1 AS Level
    FROM HR.Employees AS e
    INNER JOIN Hierarchy AS h
        ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10
)
SELECT
    h.ManagerID,
    h.EmployeeID,
    h.FullName,
    h.Level
FROM Hierarchy AS h;
GO

-- ============================================================================
-- VERIFICATION: confirm all 4 objects exist after creation
-- ============================================================================
SELECT
    OBJECT_ID('Sales.fn_GetEmployeeSales',         'IF') AS fn_GetEmployeeSales_id,
    OBJECT_ID('Sales.vw_EmployeeQuarterlySales',   'V')  AS vw_EmployeeQuarterlySales_id,
    OBJECT_ID('Sales.vw_NormalizedQuarterlySales', 'V')  AS vw_NormalizedQuarterlySales_id,
    OBJECT_ID('HR.vw_ManagerHierarchy',            'V')  AS vw_ManagerHierarchy_id;
GO
