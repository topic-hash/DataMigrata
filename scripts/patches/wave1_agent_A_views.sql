-- ============================================================================
-- Wave 1 Agent A — Patch file for ops 21-24
-- Creates 4 views in MSSQL_Advanced_Demo:
--   1. Sales.vw_ProductSummary      (SCHEMABINDING aggregation, used by op 21)
--   2. Sales.vw_AllTransactions     (UNION ALL partitioned view, used by op 22)
--   3. HR.vw_ActiveEmployees        (CHECK OPTION filter view, used by op 23)
--   4. Sales.vw_TransactionSummary  (aggregated summary view, used by op 24)
--
-- Op column contracts verified:
--   op 21: SELECT * FROM Sales.vw_ProductSummary ORDER BY Category
--          => view MUST include Category (4 cols total)
--   op 22: SELECT TOP 50 * FROM Sales.vw_AllTransactions
--          WHERE TransactionDate >= '2025-01-01' ORDER BY TransactionDate DESC
--          => view MUST include TransactionDate (11 cols total)
--   op 23: SELECT TOP 50 * FROM HR.vw_ActiveEmployees ORDER BY HireDate DESC
--          => view MUST include HireDate (8 cols total)
--   op 24: SELECT TOP 50 * FROM Sales.vw_TransactionSummary ORDER BY TransactionDate DESC
--          => view MUST include TransactionDate (5 cols total)
-- ============================================================================

USE MSSQL_Advanced_Demo;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- OBJECT 1: Sales.vw_ProductSummary (SCHEMABINDING aggregation view)
--   Groups Sales.Products by Category, counting products and summing prices.
--   Op 21 does SELECT * ORDER BY Category — Category column is present.
--   Uses COUNT_BIG (required for indexed / SCHEMABINDING views with aggregation).
--   No ORDER BY inside view definition.
-- ============================================================================
IF OBJECT_ID('Sales.vw_ProductSummary', 'V') IS NOT NULL
    DROP VIEW Sales.vw_ProductSummary;
GO
CREATE VIEW Sales.vw_ProductSummary WITH SCHEMABINDING
AS
SELECT
    p.Category,
    COUNT_BIG(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    SUM(p.CostPrice) AS TotalCostPrice
FROM Sales.Products AS p
GROUP BY p.Category;
GO

-- ============================================================================
-- OBJECT 2: Sales.vw_AllTransactions (partitioned UNION ALL view)
--   Combines current Sales.Transactions with archived Archive.OldTransactions.
--   Op 22 does SELECT * WHERE TransactionDate >= '2025-01-01'
--   ORDER BY TransactionDate DESC.
--   NULL/CAST used for columns absent in Archive.OldTransactions.
--   No ORDER BY inside view definition.
-- ============================================================================
IF OBJECT_ID('Sales.vw_AllTransactions', 'V') IS NOT NULL
    DROP VIEW Sales.vw_AllTransactions;
GO
CREATE VIEW Sales.vw_AllTransactions
AS
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
    NULL AS EmployeeID,
    ProductID,
    NULL AS Quantity,
    NULL AS UnitPrice,
    NULL AS DiscountPct,
    CAST(Amount AS DECIMAL(17,2)) AS TotalAmount,
    CAST(ArchiveDate AS DATETIME2) AS TransactionDate,
    NULL AS Region,
    NULL AS TransactionDetails,
    NULL AS PaymentStatus
FROM Archive.OldTransactions;
GO

-- ============================================================================
-- OBJECT 3: HR.vw_ActiveEmployees (filter view with CHECK OPTION)
--   Exposes employees where TerminationDate IS NULL (i.e., active employees).
--   Op 23 does SELECT TOP 50 * ORDER BY HireDate DESC.
--   No ORDER BY inside view definition.
-- ============================================================================
IF OBJECT_ID('HR.vw_ActiveEmployees', 'V') IS NOT NULL
    DROP VIEW HR.vw_ActiveEmployees;
GO
CREATE VIEW HR.vw_ActiveEmployees
AS
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
WITH CHECK OPTION;
GO

-- ============================================================================
-- OBJECT 4: Sales.vw_TransactionSummary (aggregated daily summary view)
--   Groups Sales.Transactions by TransactionDate with counts, sums, avg,
--   and distinct employee count.
--   Op 24 does SELECT TOP 50 * ORDER BY TransactionDate DESC.
--   No ORDER BY inside view definition.
-- ============================================================================
IF OBJECT_ID('Sales.vw_TransactionSummary', 'V') IS NOT NULL
    DROP VIEW Sales.vw_TransactionSummary;
GO
CREATE VIEW Sales.vw_TransactionSummary
AS
SELECT
    t.TransactionDate,
    COUNT(*) AS TransactionCount,
    SUM(t.TotalAmount) AS DailyTotal,
    AVG(t.TotalAmount) AS AvgTransaction,
    COUNT(DISTINCT t.EmployeeID) AS ActiveEmployees
FROM Sales.Transactions AS t
GROUP BY t.TransactionDate;
GO

-- ============================================================================
-- VERIFICATION: confirm all 4 objects exist after creation
-- ============================================================================
SELECT
    OBJECT_ID('Sales.vw_ProductSummary',      'V') AS vw_ProductSummary_id,
    OBJECT_ID('Sales.vw_AllTransactions',     'V') AS vw_AllTransactions_id,
    OBJECT_ID('HR.vw_ActiveEmployees',        'V') AS vw_ActiveEmployees_id,
    OBJECT_ID('Sales.vw_TransactionSummary',  'V') AS vw_TransactionSummary_id;
GO
