
-- ============================================================================
-- MSSQL SOPHISTICATED OPERATIONS DEMONSTRATION
-- Migration File with Synthetic Data Engineered for 50 Unique MSSQL Features
-- ============================================================================
-- Author: Database Systems Specialist
-- Date: 2026-07-22
-- Purpose: Demonstrate 50 operations unique to/best-in-class in MSSQL
-- ============================================================================

USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MSSQL_Advanced_Demo')
BEGIN
    ALTER DATABASE MSSQL_Advanced_Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MSSQL_Advanced_Demo;
END
GO

CREATE DATABASE MSSQL_Advanced_Demo
    COLLATE SQL_Latin1_General_CP1_CI_AS
    WITH TRUSTWORTHY ON,  -- Allows CLR assemblies
    DB_CHAINING ON;       -- Cross-database ownership chaining
GO

ALTER DATABASE MSSQL_Advanced_Demo SET RECOVERY FULL;
ALTER DATABASE MSSQL_Advanced_Demo SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE MSSQL_Advanced_Demo SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE MSSQL_Advanced_Demo SET QUERY_STORE = ON;
ALTER DATABASE MSSQL_Advanced_Demo SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
GO

USE MSSQL_Advanced_Demo;
GO

-- ============================================================================
-- SECTION 1: SCHEMA & TABLE CREATION (Synthetic Data Foundation)
-- ============================================================================

CREATE SCHEMA Sales;
CREATE SCHEMA HR;
CREATE SCHEMA Audit;
CREATE SCHEMA Archive;
CREATE SCHEMA Security;
GO

-- Core employee table with hierarchy
CREATE TABLE HR.Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    ManagerID INT NULL REFERENCES HR.Employees(EmployeeID),
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    Department NVARCHAR(50),
    Salary DECIMAL(18,2),
    HireDate DATE,
    TerminationDate DATE NULL,
    IsActive AS (CASE WHEN TerminationDate IS NULL THEN 1 ELSE 0 END) PERSISTED,
    SecurityClearanceLevel INT DEFAULT 1,
    EmployeeData XML,
    ProfilePicture VARBINARY(MAX),
    RowVersion ROWVERSION,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME(),
    ModifiedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- Sales transactions with temporal support
CREATE TABLE Sales.Transactions (
    TransactionID BIGINT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    CustomerID INT,
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(18,4),
    TotalAmount AS (Quantity * UnitPrice) PERSISTED,
    TransactionDate DATETIME2 DEFAULT SYSUTCDATETIME(),
    Region GEOGRAPHY,
    TransactionDetails JSON,
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Sales.TransactionsHistory));

-- Product catalog with filestream
CREATE TABLE Sales.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200),
    Category NVARCHAR(50),
    BasePrice DECIMAL(18,4),
    DynamicPrice DECIMAL(18,4),
    Specifications NVARCHAR(MAX),
    SearchVector AS (ProductName + ' ' + ISNULL(Category, '')) PERSISTED,
    StockLevel INT DEFAULT 0,
    ReorderPoint INT DEFAULT 10
);

-- Audit log with sequence
CREATE SEQUENCE Audit.LogSequence START WITH 1 INCREMENT BY 1;

CREATE TABLE Audit.EventLog (
    LogID BIGINT DEFAULT (NEXT VALUE FOR Audit.LogSequence) PRIMARY KEY,
    EventTime DATETIME2 DEFAULT SYSUTCDATETIME(),
    EventType NVARCHAR(50),
    TableName NVARCHAR(100),
    RecordID NVARCHAR(100),
    OldValues NVARCHAR(MAX),
    NewValues NVARCHAR(MAX),
    ChangedBy NVARCHAR(100) DEFAULT SUSER_SNAME(),
    SessionContext NVARCHAR(MAX)
);

-- Security sensitive data with encryption
CREATE TABLE Security.SensitiveData (
    DataID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    SSN VARBINARY(256),  -- Encrypted
    CreditCard VARBINARY(256), -- Encrypted
    SalaryEncrypted VARBINARY(256),
    ConfidentialNote NVARCHAR(MAX)
);

-- Archive table for partitioned data
CREATE TABLE Archive.OldTransactions (
    TransactionID BIGINT,
    Year INT,
    Month INT,
    Amount DECIMAL(18,2),
    ArchiveDate DATE DEFAULT GETDATE()
) ON [PRIMARY];

-- Memory-optimized table for high-performance lookups
CREATE TABLE Sales.CustomerCache (
    CustomerID INT PRIMARY KEY NONCLUSTERED,
    CustomerName NVARCHAR(100),
    LastOrderDate DATETIME2,
    TotalSpent DECIMAL(18,2),
    INDEX ix_CustomerName NONCLUSTERED (CustomerName)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- Full-text catalog and index
CREATE FULLTEXT CATALOG ftCatalog AS DEFAULT;
CREATE FULLTEXT INDEX ON Sales.Products(SearchVector) KEY INDEX PK__Products__B40CC6CD12345678;

-- FileTable for document storage
CREATE TABLE Archive.Documents AS FILETABLE
WITH (
    FileTable_Directory = 'DocumentStore',
    FileTable_Collate_Filename = SQL_Latin1_General_CP1_CI_AS
);

-- ============================================================================
-- SECTION 2: SYNTHETIC DATA INSERTION
-- ============================================================================

-- Insert hierarchical employee data with XML
INSERT INTO HR.Employees (ManagerID, FullName, Email, Department, Salary, HireDate, EmployeeData, SecurityClearanceLevel)
VALUES 
    (NULL, N'Alexander Sterling', 'asterling@corp.com', 'Executive', 250000.00, '2015-01-15',
     '<Employee><Skills><Skill level="Expert">Strategic Planning</Skill><Skill level="Expert">Leadership</Skill></Skills><Certifications><Cert>MBA Harvard</Cert><Cert>PMP</Cert></Certifications></Employee>', 5),
    (1, N'Victoria Chen', 'vchen@corp.com', 'Engineering', 180000.00, '2016-03-22',
     '<Employee><Skills><Skill level="Expert">Database Architecture</Skill><Skill level="Advanced">Cloud Computing</Skill></Skills></Employee>', 4),
    (1, N'Marcus Wellington', 'mwellington@corp.com', 'Sales', 160000.00, '2016-06-10',
     '<Employee><Skills><Skill level="Expert">Enterprise Sales</Skill><Skill level="Advanced">Negotiation</Skill></Skills></Employee>', 4),
    (2, N'Dr. Sarah Nakamura', 'snakamura@corp.com', 'Engineering', 140000.00, '2017-01-08',
     '<Employee><Skills><Skill level="Expert">T-SQL Optimization</Skill><Skill level="Expert">CLR Integration</Skill></Skills></Employee>', 3),
    (2, N'James O'Brien', 'jobrien@corp.com', 'Engineering', 130000.00, '2017-04-15',
     '<Employee><Skills><Skill level="Advanced">Data Engineering</Skill><Skill level="Intermediate">Machine Learning</Skill></Skills></Employee>', 3),
    (3, N'Elena Rodriguez', 'erodriguez@corp.com', 'Sales', 95000.00, '2018-02-20',
     '<Employee><Skills><Skill level="Advanced">Account Management</Skill><Skill level="Expert">CRM</Skill></Skills></Employee>', 2),
    (3, N'Raj Patel', 'rpatel@corp.com', 'Sales', 85000.00, '2018-07-12',
     '<Employee><Skills><Skill level="Intermediate">Sales Operations</Skill><Skill level="Advanced">Analytics</Skill></Skills></Employee>', 2),
    (4, N'Lisa Thompson', 'lthompson@corp.com', 'Engineering', 115000.00, '2019-03-05',
     '<Employee><Skills><Skill level="Advanced">Query Optimization</Skill><Skill level="Expert">Indexing</Skill></Skills></Employee>', 3),
    (5, N'Ahmed Hassan', 'ahassan@corp.com', 'Engineering', 105000.00, '2019-08-18',
     '<Employee><Skills><Skill level="Intermediate">ETL Development</Skill><Skill level="Advanced">SSIS</Skill></Skills></Employee>', 2),
    (6, N'Maria Gonzalez', 'mgonzalez@corp.com', 'Sales', 75000.00, '2020-01-10',
     '<Employee><Skills><Skill level="Intermediate">Inside Sales</Skill><Skill level="Beginner">Technical Sales</Skill></Skills></Employee>', 1),
    (8, N'Kevin Zhang', 'kzhang@corp.com', 'Engineering', 90000.00, '2020-06-22',
     '<Employee><Skills><Skill level="Intermediate">Database Administration</Skill><Skill level="Beginner">PowerShell</Skill></Skills></Employee>', 2),
    (4, N'Priya Sharma', 'psharma@corp.com', 'Engineering', 125000.00, '2019-11-30',
     '<Employee><Skills><Skill level="Expert">Performance Tuning</Skill><Skill level="Advanced">AlwaysOn</Skill></Skills></Employee>', 3);

-- Insert products with search vectors
INSERT INTO Sales.Products (ProductName, Category, BasePrice, Specifications)
VALUES 
    ('Quantum Database Server Enterprise', 'Software', 49999.99, 'Cores: 64, RAM: 512GB, Storage: 10TB SSD'),
    ('Quantum Database Server Standard', 'Software', 19999.99, 'Cores: 16, RAM: 128GB, Storage: 2TB SSD'),
    ('CloudSync Replication Agent', 'Software', 4999.99, 'Real-time sync, Compression, Encryption'),
    ('AI Analytics Engine Pro', 'Software', 14999.99, 'Machine Learning, Neural Networks, GPU Accelerated'),
    ('SecureVault Encryption Module', 'Security', 2999.99, 'AES-256, TDE, Column-level encryption'),
    ('DataPipeline ETL Orchestrator', 'Software', 8999.99, 'Visual designer, 200+ connectors, Scheduling'),
    ('MonitorPro Infrastructure', 'Monitoring', 3999.99, 'Real-time dashboards, Alerting, Reporting'),
    ('BackupGuard Enterprise', 'Infrastructure', 5999.99, 'Incremental, Differential, Snapshot backups'),
    ('DevOps Integration Suite', 'Development', 2499.99, 'CI/CD, Git integration, Automated testing'),
    ('Compliance Auditor', 'Security', 4499.99, 'GDPR, HIPAA, SOX compliance reporting');

-- Insert transactions with geography and JSON
INSERT INTO Sales.Transactions (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, Region, TransactionDetails)
VALUES 
    (6, 101, 1, 2, 49999.99, geography::Point(40.7128, -74.0060, 4326), 
     '{"payment_method": "wire_transfer", "terms": "net_30", "discount_code": "ENTERPRISE2026"}'),
    (6, 102, 3, 10, 4999.99, geography::Point(51.5074, -0.1278, 4326),
     '{"payment_method": "credit_card", "terms": "immediate", "po_number": "PO-2026-001"}'),
    (7, 103, 2, 5, 19999.99, geography::Point(35.6762, 139.6503, 4326),
     '{"payment_method": "ach", "terms": "net_45", "currency": "JPY"}'),
    (10, 104, 5, 20, 2999.99, geography::Point(48.8566, 2.3522, 4326),
     '{"payment_method": "credit_card", "terms": "immediate", "subscription": true}'),
    (6, 105, 4, 3, 14999.99, geography::Point(37.7749, -122.4194, 4326),
     '{"payment_method": "wire_transfer", "terms": "net_60", "implementation": "premium"}'),
    (7, 106, 6, 8, 8999.99, geography::Point(52.5200, 13.4050, 4326),
     '{"payment_method": "sepa", "terms": "net_30", "training_included": true}'),
    (10, 107, 7, 15, 3999.99, geography::Point(19.4326, -99.1332, 4326),
     '{"payment_method": "credit_card", "terms": "immediate", "support_tier": "gold"}'),
    (6, 108, 8, 4, 5999.99, geography::Point(1.3521, 103.8198, 4326),
     '{"payment_method": "wire_transfer", "terms": "net_30", "dr_site_included": true}'),
    (7, 109, 9, 25, 2499.99, geography::Point(55.7558, 37.6173, 4326),
     '{"payment_method": "credit_card", "terms": "immediate", "seats": 50}'),
    (10, 110, 10, 6, 4499.99, geography::Point(-33.8688, 151.2093, 4326),
     '{"payment_method": "wire_transfer", "terms": "net_45", "audit_frequency": "quarterly"}');

-- Insert memory-optimized customer cache
INSERT INTO Sales.CustomerCache (CustomerID, CustomerName, LastOrderDate, TotalSpent)
VALUES 
    (101, 'Global Tech Solutions Inc.', '2026-07-15', 299999.98),
    (102, 'European Data Systems', '2026-07-10', 49999.90),
    (103, 'Tokyo Digital Innovations', '2026-07-08', 99999.95),
    (104, 'Paris Cloud Services', '2026-07-12', 59999.80),
    (105, 'Silicon Valley Analytics', '2026-07-18', 44999.97);

-- Insert archive data for partitioning demo
INSERT INTO Archive.OldTransactions (TransactionID, Year, Month, Amount)
VALUES 
    (1, 2024, 1, 150000.00), (2, 2024, 1, 89000.00),
    (3, 2024, 2, 245000.00), (4, 2024, 2, 67000.00),
    (5, 2024, 3, 178000.00), (6, 2024, 3, 92000.00),
    (7, 2025, 1, 312000.00), (8, 2025, 1, 145000.00),
    (9, 2025, 2, 267000.00), (10, 2025, 2, 198000.00);

-- Insert audit events
INSERT INTO Audit.EventLog (EventType, TableName, RecordID, OldValues, NewValues)
VALUES 
    ('INSERT', 'HR.Employees', '1', NULL, '{"name": "Alexander Sterling", "dept": "Executive"}'),
    ('UPDATE', 'HR.Employees', '4', '{"salary": 120000}', '{"salary": 140000}'),
    ('DELETE', 'Sales.Products', '99', '{"name": "Legacy Module"}', NULL),
    ('INSERT', 'Sales.Transactions', '1', NULL, '{"amount": 99999.98}'),
    ('UPDATE', 'Security.SensitiveData', '1', '{"clearance": 2}', '{"clearance": 3}');

GO

-- ============================================================================
-- SECTION 3: ADVANCED OBJECTS CREATION
-- ============================================================================

-- Create a partition function and scheme
CREATE PARTITION FUNCTION pf_TransactionYear (INT)
AS RANGE RIGHT FOR VALUES (2024, 2025, 2026);

CREATE PARTITION SCHEME ps_TransactionYear
AS PARTITION pf_TransactionYear ALL TO ([PRIMARY]);

-- Create partitioned table
CREATE TABLE Sales.PartitionedSales (
    SaleID BIGINT IDENTITY(1,1),
    SaleYear INT,
    Amount DECIMAL(18,2),
    CONSTRAINT CK_Year CHECK (SaleYear >= 2020 AND SaleYear <= 2030)
) ON ps_TransactionYear(SaleYear);

INSERT INTO Sales.PartitionedSales (SaleYear, Amount)
VALUES (2023, 50000), (2024, 75000), (2025, 120000), (2026, 200000);

-- Create a view with SCHEMABINDING for indexed view
CREATE VIEW Sales.vw_ProductSummary WITH SCHEMABINDING
AS
SELECT 
    p.Category,
    COUNT_BIG(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    AVG(p.BasePrice) AS AvgBasePrice
FROM Sales.Products p
GROUP BY p.Category;
GO

-- Create unique clustered index on view (making it an indexed/materialized view)
CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSummary ON Sales.vw_ProductSummary(Category);
GO

-- Create a synonym
CREATE SYNONYM Prod FOR Sales.Products;

-- Create a user-defined table type
CREATE TYPE Sales.OrderItemType AS TABLE (
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(18,4)
);

-- Create a message type and contract for Service Broker
CREATE MESSAGE TYPE [//Corp/Orders/OrderRequest]
    VALIDATION = WELL_FORMED_XML;

CREATE MESSAGE TYPE [//Corp/Orders/OrderResponse]
    VALIDATION = WELL_FORMED_XML;

CREATE CONTRACT [//Corp/Orders/OrderContract]
    ([//Corp/Orders/OrderRequest] SENT BY INITIATOR,
     [//Corp/Orders/OrderResponse] SENT BY TARGET);

-- Create queues and services
CREATE QUEUE Sales.OrderQueue;
CREATE SERVICE [//Corp/Orders/OrderService]
    ON QUEUE Sales.OrderQueue ([//Corp/Orders/OrderContract]);

GO

-- ============================================================================
-- SECTION 4: ENCRYPTION SETUP
-- ============================================================================

-- Create database master key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Str0ngP@ssw0rd!2026#Secure';

-- Create certificate for column encryption
CREATE CERTIFICATE EmployeeDataCert
    WITH SUBJECT = 'Employee Sensitive Data Encryption';

-- Create symmetric key
CREATE SYMMETRIC KEY EmployeeSymKey
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE EmployeeDataCert;

-- Open key and insert encrypted data
OPEN SYMMETRIC KEY EmployeeSymKey
    DECRYPTION BY CERTIFICATE EmployeeDataCert;

INSERT INTO Security.SensitiveData (EmployeeID, SSN, CreditCard, SalaryEncrypted)
VALUES 
    (1, EncryptByKey(Key_GUID('EmployeeSymKey'), '123-45-6789'), 
     EncryptByKey(Key_GUID('EmployeeSymKey'), '4532-1234-5678-9012'),
     EncryptByKey(Key_GUID('EmployeeSymKey'), '250000.00')),
    (2, EncryptByKey(Key_GUID('EmployeeSymKey'), '987-65-4321'),
     EncryptByKey(Key_GUID('EmployeeSymKey'), '5500-9876-5432-1098'),
     EncryptByKey(Key_GUID('EmployeeSymKey'), '180000.00'));

CLOSE SYMMETRIC KEY EmployeeSymKey;
GO

-- ============================================================================
-- SECTION 5: CLR & EXTERNAL OBJECTS (Conceptual - would need actual CLR assembly)
-- ============================================================================

-- Note: Actual CLR registration requires external assembly file
-- Below is the T-SQL wrapper that would be used:

/*
CREATE ASSEMBLY StringUtilities
    FROM 'C:\Assemblies\StringUtilities.dll'
    WITH PERMISSION_SET = SAFE;

CREATE FUNCTION dbo.RegexMatch(@pattern NVARCHAR(MAX), @input NVARCHAR(MAX))
RETURNS BIT
AS EXTERNAL NAME StringUtilities.[StringUtilities.RegexFunctions].Match;
*/

-- Create a statistical semantic search catalog (requires Full-Text Search feature)
-- CREATE SEMANTIC LANGUAGE MODEL DATABASE;  -- One-time server setup

PRINT 'Database MSSQL_Advanced_Demo created successfully with synthetic data.';
GO
