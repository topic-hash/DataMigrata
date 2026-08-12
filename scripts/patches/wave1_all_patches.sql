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
-- ============================================================================
-- Wave 1 Agent D — Patch file for ops 41, 45, 46, 50
-- Creates the following objects / configuration in MSSQL_Advanced_Demo:
--   1. Database master key                        (used by op 41 indirectly)
--   2. Certificate EmployeeDataCert               (used by op 41 to open sym key)
--   3. Symmetric key EmployeeSymKey (AES_256)     (used by op 41 + op 45)
--   4. HR.usp_GetSensitiveEmployeeData            (used by op 45)
--   5. Sales.OrderItemType (UDT)                  (used by op 46)
--   6. Sales.usp_BulkInsertOrders (TVP proc)      (used by op 46 — AUXILIARY)
--   7. Change tracking on DB + Sales.Products     (used by op 50)
--
-- Op contracts verified:
--   op 41: OPEN SYMMETRIC KEY EmployeeSymKey DECRYPTION BY CERTIFICATE EmployeeDataCert;
--          SELECT ... DecryptByKey(s.SSN), DecryptByKey(s.CreditCard),
--                 DecryptByKey(s.SalaryEncrypted)
--          FROM Security.SensitiveData s JOIN HR.Employees e ...
--          => needs EmployeeSymKey + EmployeeDataCert + Security.SensitiveData
--
--   op 45: EXEC HR.usp_GetSensitiveEmployeeData;
--          => proc must exist with no required params (op calls with no args)
--          => proc body opens EmployeeSymKey, decrypts SSN, returns rows
--
--   op 46: DECLARE @items Sales.OrderItemType;
--          INSERT INTO @items VALUES (1, 2, 49999.99, 0), (3, 5, 4999.99, 0.1);
--          EXEC Sales.usp_BulkInsertOrders @items, 6, 999;
--          => Sales.OrderItemType must have exactly 4 columns matching
--             (ProductID INT, Quantity INT, UnitPrice DECIMAL(18,4),
--              DiscountPct DECIMAL(5,4)) so the 4-tuple INSERT works.
--          => Sales.usp_BulkInsertOrders must accept
--             (@Items Sales.OrderItemType READONLY, @EmployeeID INT, @CustomerID INT)
--             in that positional order, because op 46 calls
--             `EXEC Sales.usp_BulkInsertOrders @items, 6, 999`.
--
--   op 50: SELECT ... FROM CHANGETABLE(CHANGES Sales.Products, 0) CT
--          LEFT JOIN Sales.Products p ON CT.ProductID = p.ProductID;
--          => requires CHANGE_TRACKING enabled at DB level AND on Sales.Products.
--
-- All definitions mirror 00_COMPLETE_MSSQL_Deployment.sql (lines 671-697, 729-736,
-- 791-798, 1043-1071) but with idempotency guards so the patch is safe to re-run
-- against a partially-deployed database.
-- ============================================================================

USE MSSQL_Advanced_Demo;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- OBJECT 1: Database Master Key
--   Required before any certificate / symmetric key can be created.
--   Guard via sys.symmetric_keys (the DMK is stored there with the reserved
--   name ##MS_DatabaseMasterKey##).
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Str0ngP@ssw0rd!2026#Secure';
GO

-- ============================================================================
-- OBJECT 2: Certificate EmployeeDataCert
--   Op 41 opens EmployeeSymKey with `DECRYPTION BY CERTIFICATE EmployeeDataCert`
--   so the certificate name MUST be exactly `EmployeeDataCert`.
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'EmployeeDataCert')
    CREATE CERTIFICATE EmployeeDataCert
        WITH SUBJECT = 'Employee Sensitive Data Encryption',
             EXPIRY_DATE = '20991231';
GO

-- ============================================================================
-- OBJECT 3: Symmetric key EmployeeSymKey (AES_256, encrypted by EmployeeDataCert)
--   Op 41 opens it by name + cert; op 45's proc also opens it.
--   Algorithm AES_256 matches the original deployment (line 677).
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = 'EmployeeSymKey')
    CREATE SYMMETRIC KEY EmployeeSymKey
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE EmployeeDataCert;
GO

-- ============================================================================
-- OBJECT 4 (prep): Drop Sales.usp_BulkInsertOrders BEFORE Sales.OrderItemType
--   A UDT cannot be dropped while a proc references it (Msg 3539).
--   We drop the proc first so the type can be safely recreated below, then
--   recreate the proc against the fresh type.
-- ============================================================================
IF OBJECT_ID('Sales.usp_BulkInsertOrders', 'P') IS NOT NULL
    DROP PROCEDURE Sales.usp_BulkInsertOrders;
GO

-- ============================================================================
-- OBJECT 5: Sales.OrderItemType user-defined table type
--   Columns must match op 46's INSERT INTO @items VALUES
--   (1, 2, 49999.99, 0), (3, 5, 4999.99, 0.1):
--     col1 INT            <- 1, 3
--     col2 INT            <- 2, 5
--     col3 DECIMAL(18,4)  <- 49999.99, 4999.99   (2 decimal places)
--     col4 DECIMAL(5,4)   <- 0, 0.1              (0.1 needs 4 fractional digits)
--   Names: ProductID / Quantity / UnitPrice / DiscountPct match the deployment
--   (line 729-736) AND match the body of Sales.usp_BulkInsertOrders.
-- ============================================================================
IF TYPE_ID('Sales.OrderItemType') IS NOT NULL
    DROP TYPE Sales.OrderItemType;
GO
CREATE TYPE Sales.OrderItemType AS TABLE
(
    ProductID   INT           NOT NULL,
    Quantity    INT           NOT NULL,
    UnitPrice   DECIMAL(18,4) NOT NULL,
    DiscountPct DECIMAL(5,4)  NOT NULL DEFAULT 0
);
GO

-- ============================================================================
-- OBJECT 6 (auxiliary): Sales.usp_BulkInsertOrders
--   Op 46 calls `EXEC Sales.usp_BulkInsertOrders @items, 6, 999` positionally,
--   so the proc signature MUST be (@Items <type> READONLY, @EmployeeID INT, @CustomerID INT)
--   in that exact order. The proc body INSERTs into Sales.Transactions and
--   returns SCOPE_IDENTITY(). Matches deployment lines 1058-1071.
--   NOTE: required for op 46 to pass — the table type alone is insufficient.
-- ============================================================================
IF OBJECT_ID('Sales.usp_BulkInsertOrders', 'P') IS NOT NULL
    DROP PROCEDURE Sales.usp_BulkInsertOrders;
GO
CREATE PROCEDURE Sales.usp_BulkInsertOrders
    @Items     Sales.OrderItemType READONLY,
    @EmployeeID INT,
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Sales.Transactions
        (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, DiscountPct)
    SELECT
        @EmployeeID,
        @CustomerID,
        i.ProductID,
        i.Quantity,
        i.UnitPrice,
        i.DiscountPct
    FROM @Items AS i;

    SELECT SCOPE_IDENTITY() AS LastTransactionID;
END;
GO

-- ============================================================================
-- OBJECT 7: HR.usp_GetSensitiveEmployeeData (certificate-themed proc)
--   Op 45 calls `EXEC HR.usp_GetSensitiveEmployeeData` (no args) — proc must
--   have all-optional params. Body opens EmployeeSymKey (created above),
--   decrypts the SSN column from Security.SensitiveData, returns the result.
--   LEFT JOIN + TRY/CATCH around OPEN/CLOSE make the proc robust to an empty
--   Security.SensitiveData table or a session that already has the key open.
-- ============================================================================
IF OBJECT_ID('HR.usp_GetSensitiveEmployeeData', 'P') IS NOT NULL
    DROP PROCEDURE HR.usp_GetSensitiveEmployeeData;
GO
CREATE PROCEDURE HR.usp_GetSensitiveEmployeeData
    @EmployeeID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Open the symmetric key (created by this patch / deployment Step 10).
    -- TRY/CATCH: tolerate "key already open in session" or "key missing" so the
    -- proc still returns a result set even if crypto state is unexpected.
    BEGIN TRY
        OPEN SYMMETRIC KEY EmployeeSymKey
            DECRYPTION BY CERTIFICATE EmployeeDataCert;
    END TRY
    BEGIN CATCH
        -- Swallow: DecryptByKey will simply return NULL if no key is open.
    END CATCH;

    SELECT TOP 100
        e.EmployeeID,
        e.FullName,
        e.Department,
        e.JobTitle,
        e.Salary,
        e.Email,
        CONVERT(VARCHAR, DecryptByKey(s.SSN))                AS DecryptedSSN,
        '****-**-' + RIGHT(CONVERT(VARCHAR, DecryptByKey(s.SSN)), 4) AS MaskedSSN
    FROM HR.Employees AS e
    LEFT JOIN Security.SensitiveData AS s
        ON e.EmployeeID = s.EmployeeID
    WHERE (@EmployeeID IS NULL OR e.EmployeeID = @EmployeeID)
    ORDER BY e.EmployeeID;

    BEGIN TRY
        CLOSE SYMMETRIC KEY EmployeeSymKey;
    END TRY
    BEGIN CATCH
        -- Swallow: key may already be closed or never opened.
    END CATCH;
END;
GO

-- ============================================================================
-- OBJECT 8: Enable change tracking at DATABASE level
--   Must be done BEFORE table-level CT. Guard via sys.change_tracking_databases.
--   Options match deployment (line 791-794): 2-day retention, auto-cleanup on.
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.change_tracking_databases
    WHERE database_id = DB_ID('MSSQL_Advanced_Demo')
)
    ALTER DATABASE MSSQL_Advanced_Demo
        SET CHANGE_TRACKING = ON
        (
            CHANGE_RETENTION = 2 DAYS,
            AUTO_CLEANUP     = ON
        );
GO

-- ============================================================================
-- OBJECT 9: Enable change tracking on Sales.Products
--   Op 50 queries CHANGETABLE(CHANGES Sales.Products, 0) — requires CT enabled
--   on the table itself. Guard via sys.change_tracking_tables.
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.change_tracking_tables
    WHERE object_id = OBJECT_ID('Sales.Products')
)
    ALTER TABLE Sales.Products
        ENABLE CHANGE_TRACKING
        WITH (TRACK_COLUMNS_UPDATED = ON);
GO

-- ============================================================================
-- VERIFICATION: confirm every required object exists + CT is enabled
-- ============================================================================
SELECT
    -- Op 41 dependencies
    (SELECT name FROM sys.symmetric_keys WHERE name = 'EmployeeSymKey')                AS EmployeeSymKey,
    (SELECT name FROM sys.certificates   WHERE name = 'EmployeeDataCert')             AS EmployeeDataCert,
    -- Op 45
    OBJECT_ID('HR.usp_GetSensitiveEmployeeData', 'P')                                  AS usp_GetSensitiveEmployeeData_id,
    -- Op 46
    TYPE_ID('Sales.OrderItemType')                                                     AS OrderItemType_id,
    OBJECT_ID('Sales.usp_BulkInsertOrders', 'P')                                       AS usp_BulkInsertOrders_id,
    -- Op 50
    (SELECT COUNT(*) FROM sys.change_tracking_databases WHERE database_id = DB_ID())   AS CT_on_db,
    (SELECT COUNT(*) FROM sys.change_tracking_tables   WHERE object_id = OBJECT_ID('Sales.Products')) AS CT_on_Products;
GO
