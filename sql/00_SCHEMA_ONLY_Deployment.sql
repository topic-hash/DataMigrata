-- Extract from 00_COMPLETE_MSSQL_Deployment.sql everything up to STEP 7
-- Then skip data population and continue from STEP 8 onward
-- The SET-based population script will handle data separately

USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'MSSQL_Advanced_Demo')
BEGIN
    ALTER DATABASE MSSQL_Advanced_Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MSSQL_Advanced_Demo;
END
GO

CREATE DATABASE MSSQL_Advanced_Demo
    COLLATE SQL_Latin1_General_CP1_CI_AS
    WITH 
        TRUSTWORTHY ON,
        DB_CHAINING ON;
GO

ALTER DATABASE MSSQL_Advanced_Demo SET RECOVERY FULL;
-- READ_COMMITTED_SNAPSHOT OFF for memory-optimized table compatibility
ALTER DATABASE MSSQL_Advanced_Demo SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE MSSQL_Advanced_Demo SET QUERY_STORE = ON;
ALTER DATABASE MSSQL_Advanced_Demo SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 1000
);
ALTER DATABASE MSSQL_Advanced_Demo SET COMPATIBILITY_LEVEL = 160;
ALTER DATABASE MSSQL_Advanced_Demo SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE MSSQL_Advanced_Demo SET AUTO_UPDATE_STATISTICS ON;
GO

ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP MSSQL_Advanced_Demo_mod CONTAINS MEMORY_OPTIMIZED_DATA;
ALTER DATABASE MSSQL_Advanced_Demo
    ADD FILE (NAME = N'MSSQL_Advanced_Demo_mod',
               FILENAME = N'/var/opt/mssql/data/MSSQL_Advanced_Demo_mod')
    TO FILEGROUP MSSQL_Advanced_Demo_mod;
GO

USE MSSQL_Advanced_Demo;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Sales')
    EXEC('CREATE SCHEMA Sales');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'HR')
    EXEC('CREATE SCHEMA HR');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Audit')
    EXEC('CREATE SCHEMA Audit');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Archive')
    EXEC('CREATE SCHEMA Archive');
IF NOT EXISTS (SELECT 1 FROM syschemas WHERE name = 'Security')
    EXEC('CREATE SCHEMA Security');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Staging')
    EXEC('CREATE SCHEMA Staging');
GO

CREATE TABLE HR.Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    ManagerID INT NULL REFERENCES HR.Employees(EmployeeID),
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    Department NVARCHAR(50),
    JobTitle NVARCHAR(100),
    Salary DECIMAL(18,2),
    HireDate DATE,
    TerminationDate DATE NULL,
    IsActive AS (CASE WHEN TerminationDate IS NULL THEN 1 ELSE 0 END) PERSISTED,
    SecurityClearanceLevel INT DEFAULT 1,
    EmployeeData XML,
    ProfilePicture VARBINARY(MAX),
    RowVersion ROWVERSION,
    CreatedAt DATETIME2(0) DEFAULT SYSUTCDATETIME(),
    ModifiedAt DATETIME2(0) DEFAULT SYSUTCDATETIME()
);

CREATE TABLE HR.OrgChart (
    OrgNode HIERARCHYID PRIMARY KEY CLUSTERED,
    OrgLevel AS OrgNode.GetLevel(),
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    PositionTitle NVARCHAR(100),
    Department NVARCHAR(50)
);

CREATE TABLE Sales.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200) NOT NULL,
    Category NVARCHAR(50),
    SubCategory NVARCHAR(50),
    BasePrice DECIMAL(18,4),
    CostPrice DECIMAL(18,4),
    Specifications NVARCHAR(MAX),
    SearchVector AS (ProductName + ' ' + ISNULL(Category, '') + ' ' + ISNULL(SubCategory, '')) PERSISTED,
    StockLevel INT DEFAULT 0,
    ReorderPoint INT DEFAULT 10,
    IsDiscontinued BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

CREATE TABLE Sales.Transactions (
    TransactionID BIGINT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    CustomerID INT NOT NULL,
    ProductID INT REFERENCES Sales.Products(ProductID),
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,4) NOT NULL,
    DiscountPct DECIMAL(5,4) DEFAULT 0,
    TotalAmount AS (Quantity * UnitPrice * (1 - DiscountPct)) PERSISTED,
    TransactionDate DATETIME2 DEFAULT SYSUTCDATETIME(),
    Region GEOGRAPHY,
    TransactionDetails NVARCHAR(MAX),
    PaymentStatus NVARCHAR(20) DEFAULT 'pending',
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Sales.TransactionsHistory));

CREATE TABLE Sales.CustomerCache (
    CustomerID INT NOT NULL PRIMARY KEY NONCLUSTERED,
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100),
    RegionCode NVARCHAR(10),
    LastOrderDate DATETIME2,
    TotalSpent DECIMAL(18,2),
    OrderCount INT DEFAULT 0,
    INDEX ix_CustomerName NONCLUSTERED (CustomerName),
    INDEX ix_Region NONCLUSTERED (RegionCode)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

CREATE TABLE Sales.HighSpeedLookup (
    LookupKey INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1000000),
    DataValue NVARCHAR(200) NOT NULL,
    Category NVARCHAR(50)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

CREATE TABLE Audit.EventLog (
    EventID INT IDENTITY(1,1) PRIMARY KEY,
    EventType NVARCHAR(50) NOT NULL,
    EventTime DATETIME2 DEFAULT SYSUTCDATETIME(),
    Severity NVARCHAR(20),
    Message NVARCHAR(MAX),
    SourceComponent NVARCHAR(100),
    RelatedEntity NVARCHAR(200)
);

CREATE TABLE Security.SensitiveData (
    RecordID INT IDENTITY(1,1) PRIMARY KEY,
    RecordType NVARCHAR(50) NOT NULL,
    DataClassification NVARCHAR(50),
    EncryptedValue VARBINARY(MAX),
    Owner NVARCHAR(100),
    AccessLevel INT,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

CREATE TABLE Archive.OldTransactions (
    ArchiveID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT,
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(18,4),
    TransactionDate DATETIME2,
    Region GEOGRAPHY
);

CREATE TABLE Staging.ETLSource (
    SourceID INT IDENTITY(1,1) PRIMARY KEY,
    SourceSystem NVARCHAR(100),
    RecordCount INT,
    LastExtractDate DATETIME2,
    ExtractStatus NVARCHAR(20),
    TargetTable NVARCHAR(200),
    Notes NVARCHAR(MAX)
);
GO

-- Partition function and scheme
CREATE PARTITION FUNCTION pf_TransactionYear(DATE)
    AS RANGE RIGHT FOR VALUES ('2021-01-01', '2022-01-01', '2023-01-01', '2024-01-01', '2025-01-01', '2026-01-01');
GO

CREATE PARTITION SCHEME ps_TransactionYear
    AS RANGE RIGHT TO ('2027-01-01')
    PARTITIONS
    (FG_Transactions2021, FG_Transactions2022, FG_Transactions2023, FG_Transactions2024, FG_Transactions2025, FG_Transactions2026);

-- Filegroups for partitioned table
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP FG_Transactions2021;
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP FG_Transactions2022;
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP FG_Transactions2023;
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP FG_Transactions2024;
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP FG_Transactions2025;
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP FG_Transactions2026;
GO

CREATE TABLE Sales.PartitionedSales (
    SaleID INT IDENTITY(1,1),
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(18,4),
    SaleDate DATE NOT NULL,
    Region NVARCHAR(50),
    CustomerID INT,
    CONSTRAINT PK_PartitionedSales PRIMARY KEY (SaleID, SaleDate)
) ON ps_TransactionYear(SaleDate);
GO

-- STEP 6: FULL-TEXT CATALOG
CREATE FULLTEXT CATALOG ftCatalog AS DEFAULT;
GO

-- STEP 8: INDEXES
CREATE INDEX IX_Employees_Dept ON HR.Employees(Department);
CREATE INDEX IX_Employees_Manager ON HR.Employees(ManagerID);
CREATE INDEX IX_Employees_Salary ON HR.Employees(Salary);
GO

CREATE INDEX IX_Products_Category ON Sales.Products(Category);
CREATE INDEX IX_Products_Price ON Sales.Products(BasePrice);
GO

CREATE INDEX IX_Transactions_Emp ON Sales.Transactions(EmployeeID);
CREATE INDEX IX_Transactions_Prod ON Sales.Transactions(ProductID);
CREATE INDEX IX_Transactions_Date ON Sales.Transactions(TransactionDate);
CREATE INDEX IX_Transactions_Status ON Sales.Transactions(PaymentStatus);
GO

CREATE INDEX IX_Audit_EventType ON Audit.EventLog(EventType);
CREATE INDEX IX_Audit_EventTime ON Audit.EventLog(EventTime);
GO

-- STEP 9: FULL-TEXT INDEX
CREATE UNIQUE INDEX UX_Products_ProductName ON Sales.Products(ProductName);
GO

CREATE FULLTEXT INDEX ON Sales.Products(ProductName, Specifications) 
KEY INDEX UX_Products_ProductName
WITH STOPLIST = SYSTEM;
GO

-- STEP 10: ENCRYPTION
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'DataMigrata_MasterKey_2026!';
CREATE CERTIFICATE Cert_DataMigrata ENCRYPTION BY PASSWORD = 'DataMigrata_Cert_2026!';
GO

CREATE SYMMETRIC KEY SymKey_DataMigrata WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE Cert_DataMigrata;
GO

-- STEP 11: CHANGE TRACKING
ALTER TABLE HR.Employees ENABLE CHANGE_TRACKING;
ALTER TABLE Sales.Products ENABLE CHANGE_TRACKING;
ALTER TABLE Sales.Transactions ENABLE CHANGE_TRACKING;
GO

-- STEP 12: COLUMNSTORE INDEX
CREATE NONCLUSTERED COLUMNSTORE INDEX IX_CS_Transactions 
ON Sales.Transactions (EmployeeID, ProductID, TransactionDate, PaymentStatus);
GO

-- STEP 13: VIEWS
CREATE VIEW Sales.vw_ProductSummary WITH SCHEMABINDING
AS
SELECT 
    p.Category,
    COUNT_BIG(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    SUM(p.CostPrice) AS TotalCostPrice
FROM Sales.Products p
GROUP BY p.Category;
GO

CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSummary ON Sales.vw_ProductSummary(Category);
GO

IF OBJECT_ID('tempdb..#Names') IS NOT NULL DROP TABLE #Names;

-- Synonym
IF EXISTS (SELECT 1 FROM sys.synonyms WHERE name = 'Prod') DROP SYNONYM Prod;
CREATE SYNONYM Prod FOR Sales.Products;
GO

-- STEP 15: ROW-LEVEL SECURITY (will be re-enabled after data population)
-- SKIP for now - data population script will not trigger RLS

-- STEP 16: DYNAMIC DATA MASKING
ALTER TABLE HR.Employees
ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE HR.Employees
ALTER COLUMN Salary ADD MASKED WITH (FUNCTION = 'default()');
GO

PRINT 'Schema deployment complete. Run 01_MSSQL_Populate_Data_SetBased.sql next.';
GO
