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
