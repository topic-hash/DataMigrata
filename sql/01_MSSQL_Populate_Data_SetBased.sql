SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
USE MSSQL_Advanced_Demo;
GO

-- ============================================================================
-- STREAMLINED DATA POPULATION (SET-BASED, NO WHILE LOOPS)
-- ============================================================================

-- Disable constraints for bulk insert
ALTER TABLE HR.Employees NOCHECK CONSTRAINT ALL;
GO

-- 1. Populate HR.Employees (5000 rows) - SET BASED
INSERT INTO HR.Employees (ManagerID, FullName, Email, Department, JobTitle, Salary, HireDate, SecurityClearanceLevel)
SELECT TOP 5000
    NULL,
    'Employee_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR(10)),
    'employee' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR(10)) + '@dataMigrata.com',
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
        WHEN 0 THEN 'Engineering' WHEN 1 THEN 'Sales' WHEN 2 THEN 'Marketing'
        WHEN 3 THEN 'HR' WHEN 4 THEN 'Finance' WHEN 5 THEN 'Operations'
        WHEN 6 THEN 'Legal' WHEN 7 THEN 'R&D' WHEN 8 THEN 'Customer Success'
        ELSE 'IT' END,
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
        WHEN 0 THEN 'Senior Engineer' WHEN 1 THEN 'Account Executive' WHEN 2 THEN 'Marketing Manager'
        WHEN 3 THEN 'HR Specialist' WHEN 4 THEN 'Financial Analyst' WHEN 5 THEN 'Operations Director'
        WHEN 6 THEN 'Legal Counsel' WHEN 7 THEN 'Research Scientist' WHEN 8 THEN 'Customer Success Manager'
        ELSE 'IT Architect' END,
    55000 + (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 150) * 1000,
    DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 3650), CAST('2026-07-22' AS DATE)),
    (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5) + 1
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

-- Fix ManagerID hierarchy (first 100 are managers, rest report to managers)
UPDATE HR.Employees
SET ManagerID = CASE WHEN EmployeeID <= 100 THEN NULL ELSE (EmployeeID % 100) + 1 END;
GO

ALTER TABLE HR.Employees WITH CHECK CHECK CONSTRAINT ALL;
GO

-- 2. Populate HR.OrgChart (100 rows) - SET BASED
INSERT INTO HR.OrgChart (OrgNode, EmployeeID, PositionTitle, Department)
SELECT TOP 100
    HIERARCHYID::Parse('/' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR)),
    ROW_NUMBER() OVER (ORDER BY (SELECT 1)),
    'Position_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR),
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
        WHEN 0 THEN 'Engineering' WHEN 1 THEN 'Sales' WHEN 2 THEN 'Marketing'
        WHEN 3 THEN 'HR' WHEN 4 THEN 'Finance' WHEN 5 THEN 'Operations'
        WHEN 6 THEN 'Legal' WHEN 7 THEN 'R&D' WHEN 8 THEN 'Customer Success'
        ELSE 'IT' END
FROM master..spt_values WHERE type = 'P';
GO

-- 3. Populate Sales.Products (1000 rows) - SET BASED
INSERT INTO Sales.Products (ProductName, Category, SubCategory, BasePrice, CostPrice, Specifications, StockLevel, ReorderPoint)
SELECT TOP 1000
    SubCat + ' ' + Cat + ' Solution ' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR),
    Cat, SubCat,
    99.99 + (ABS(CHECKSUM(NEWID())) % 99000),
    (99.99 + (ABS(CHECKSUM(NEWID())) % 99000)) * 0.6,
    'Specs for product ' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR),
    ABS(CHECKSUM(NEWID())) % 1000,
    10 + ABS(CHECKSUM(NEWID())) % 50
FROM (
    SELECT TOP 1000
        CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
            WHEN 0 THEN 'Software' WHEN 1 THEN 'Hardware' WHEN 2 THEN 'Services'
            WHEN 3 THEN 'Security' WHEN 4 THEN 'Cloud' WHEN 5 THEN 'Analytics'
            WHEN 6 THEN 'Infrastructure' WHEN 7 THEN 'Development' WHEN 8 THEN 'Monitoring'
            ELSE 'Storage' END AS Cat,
        CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
            WHEN 0 THEN 'Enterprise' WHEN 1 THEN 'Standard' WHEN 2 THEN 'Professional'
            WHEN 3 THEN 'Starter' WHEN 4 THEN 'Premium' WHEN 5 THEN 'Basic'
            WHEN 6 THEN 'Advanced' WHEN 7 THEN 'Ultimate' WHEN 8 THEN 'Lite'
            ELSE 'Pro' END AS SubCat
    FROM master..spt_values a CROSS JOIN master..spt_values b
    WHERE a.type = 'P' AND b.type = 'P'
) t;
GO

-- 4. Populate Sales.Transactions (5000 rows) - SET BASED
ALTER TABLE Sales.Transactions NOCHECK CONSTRAINT ALL;
GO

INSERT INTO Sales.Transactions (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, DiscountPct, TransactionDetails, PaymentStatus)
SELECT TOP 5000
    e.EmployeeID,
    1000 + ABS(CHECKSUM(NEWID())) % 9000,
    p.ProductID,
    1 + ABS(CHECKSUM(NEWID())) % 50,
    p.BasePrice,
    CASE WHEN ABS(CHECKSUM(NEWID())) % 10 = 0 THEN 0.15 ELSE 0 END,
    JSON_OBJECT(
        'payment_method': (SELECT TOP 1 val FROM (VALUES ('wire_transfer'),('credit_card'),('ach'),('sepa'),('crypto')) AS v(val) ORDER BY NEWID()),
        'terms': (SELECT TOP 1 val FROM (VALUES ('net_30'),('net_60'),('immediate'),('net_45')) AS v(val) ORDER BY NEWID()),
        'po_number': 'PO-' + CAST(YEAR(GETDATE()) AS VARCHAR) + '-' + RIGHT('0000' + CAST(n AS VARCHAR), 4),
        'processed': CAST(ABS(CHECKSUM(NEWID())) % 2 AS BIT),
        'discount_code': CASE WHEN n % 10 = 0 THEN 'SAVE15' ELSE NULL END
    ),
    (SELECT TOP 1 val FROM (VALUES ('pending'),('completed'),('refunded'),('disputed')) AS v(val) ORDER BY NEWID())
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS n) nums
CROSS JOIN (SELECT TOP 1 EmployeeID FROM HR.Employees ORDER BY NEWID()) e
CROSS JOIN (SELECT TOP 1 ProductID, BasePrice FROM Sales.Products ORDER BY NEWID()) p;
GO

ALTER TABLE Sales.Transactions WITH CHECK CHECK CONSTRAINT ALL;
GO

-- 5. Populate Sales.CustomerCache (2000 rows)
INSERT INTO Sales.CustomerCache (CustomerID, CustomerName, Email, RegionCode, LastOrderDate, TotalSpent, OrderCount)
SELECT TOP 2000
    1000 + ROW_NUMBER() OVER (ORDER BY (SELECT 1)),
    'Customer ' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR) + ' ' +
        CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5)
            WHEN 0 THEN 'Corp' WHEN 1 THEN 'Ltd' WHEN 2 THEN 'Inc' WHEN 3 THEN 'LLC' ELSE 'GmbH' END,
    'contact' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR) + '@customer.com',
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5)
        WHEN 0 THEN 'NA' WHEN 1 THEN 'EU' WHEN 2 THEN 'APAC' WHEN 3 THEN 'LATAM' ELSE 'MEA' END,
    DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 365), CAST('2026-07-22' AS DATE)),
    ABS(CHECKSUM(NEWID())) % 1000000,
    ABS(CHECKSUM(NEWID())) % 500
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

-- 6. Populate Sales.HighSpeedLookup (1000 rows)
INSERT INTO Sales.HighSpeedLookup (LookupKey, DataValue, Category)
SELECT TOP 1000
    'KEY_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR),
    'Value_' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS VARCHAR),
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5)
        WHEN 0 THEN 'Config' WHEN 1 THEN 'Cache' WHEN 2 THEN 'Session' WHEN 3 THEN 'Metadata' ELSE 'Index' END
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

-- 7. Populate remaining tables (same pattern as deployment script - these use small data, WHILE loops work)
DECLARE @a INT = 1;
WHILE @a <= 3000
BEGIN
    INSERT INTO Archive.OldTransactions (EmployeeID, ProductID, Quantity, UnitPrice, TransactionDate, Region)
    VALUES (
        (@a % 5000) + 1,
        (@a % 1000) + 1,
        1 + @a % 20,
        10.00 + @a % 500,
        DATEADD(DAY, -@a, CAST('2025-01-01' AS DATE)),
        geography::Point(40.7 + (@a % 100) * 0.01, -74.0 + (@a % 100) * 0.01, 4326)
    );
    SET @a = @a + 1;
END
GO

-- Populate PartitionedSales (2000 rows)
INSERT INTO Sales.PartitionedSales (ProductID, Quantity, UnitPrice, SaleDate, Region, CustomerID)
SELECT TOP 2000
    (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 1000) + 1,
    1 + ABS(CHECKSUM(NEWID())) % 20,
    10.00 + ABS(CHECKSUM(NEWID())) % 500,
    DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 1825), CAST('2026-07-22' AS DATE)),
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 4)
        WHEN 0 THEN 'North' WHEN 1 THEN 'South' WHEN 2 THEN 'East' ELSE 'West' END,
    1000 + ROW_NUMBER() OVER (ORDER BY (SELECT 1))
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

-- Populate Audit.EventLog (1000 rows)
INSERT INTO Audit.EventLog (EventType, Severity, Message, SourceComponent, RelatedEntity)
SELECT TOP 1000
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5)
        WHEN 0 THEN 'LOGIN' WHEN 1 THEN 'QUERY' WHEN 2 THEN 'DML' WHEN 3 THEN 'DDL' ELSE 'SECURITY' END,
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 3)
        WHEN 0 THEN 'Low' WHEN 1 THEN 'Medium' ELSE 'High' END,
    'Event message ' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR) + ' at ' + CAST(GETDATE() AS VARCHAR),
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 4)
        WHEN 0 THEN 'AuthService' WHEN 1 THEN 'QueryEngine' WHEN 2 THEN 'DataPipeline' ELSE 'SecurityMonitor' END,
    'Entity_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR)
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

-- Populate Security.SensitiveData (100 rows)
INSERT INTO Security.SensitiveData (RecordType, DataClassification, EncryptedValue, Owner, AccessLevel)
SELECT TOP 100
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 3)
        WHEN 0 THEN 'PII' WHEN 1 THEN 'Financial' ELSE 'Medical' END,
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 4)
        WHEN 0 THEN 'Confidential' WHEN 1 THEN 'Restricted' WHEN 2 THEN 'Internal' ELSE 'Public' END,
    ENCRYPTBYCERT(CERT_ID('Cert_DataMigrata'), 'SensitiveData_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR)),
    'Owner_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR),
    ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5
FROM master..spt_values WHERE type = 'P';
GO

-- Populate Staging.ETLSource (500 rows)
INSERT INTO Staging.ETLSource (SourceSystem, RecordCount, LastExtractDate, ExtractStatus, TargetTable)
SELECT TOP 500
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5)
        WHEN 0 THEN 'Oracle_HR' WHEN 1 THEN 'Oracle_Finance' WHEN 2 THEN 'Oracle_Sales' WHEN 3 THEN 'Oracle_Inventory' ELSE 'Oracle_Customers' END,
    100 + ABS(CHECKSUM(NEWID())) % 10000,
    DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 30), CAST('2026-07-22' AS DATE)),
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 3)
        WHEN 0 THEN 'Pending' WHEN 1 THEN 'Completed' ELSE 'Failed' END,
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5)
        WHEN 0 THEN 'HR.Employees' WHEN 1 THEN 'Sales.Products' WHEN 2 THEN 'Sales.Transactions'
        WHEN 3 THEN 'Audit.EventLog' ELSE 'Security.SensitiveData' END
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

-- Verification
SELECT [TableName], [RowCount] FROM (
    SELECT 'HR.Employees' AS [TableName], COUNT(*) AS [RowCount] FROM HR.Employees
    UNION ALL SELECT 'HR.OrgChart', COUNT(*) FROM HR.OrgChart
    UNION ALL SELECT 'Sales.Products', COUNT(*) FROM Sales.Products
    UNION ALL SELECT 'Sales.Transactions', COUNT(*) FROM Sales.Transactions
    UNION ALL SELECT 'Sales.CustomerCache', COUNT(*) FROM Sales.CustomerCache
    UNION ALL SELECT 'Sales.HighSpeedLookup', COUNT(*) FROM Sales.HighSpeedLookup
    UNION ALL SELECT 'Archive.OldTransactions', COUNT(*) FROM Archive.OldTransactions
    UNION ALL SELECT 'Sales.PartitionedSales', COUNT(*) FROM Sales.PartitionedSales
    UNION ALL SELECT 'Audit.EventLog', COUNT(*) FROM Audit.EventLog
    UNION ALL SELECT 'Security.SensitiveData', COUNT(*) FROM Security.SensitiveData
    UNION ALL SELECT 'Staging.ETLSource', COUNT(*) FROM Staging.ETLSource
) t ORDER BY [TableName];
GO
