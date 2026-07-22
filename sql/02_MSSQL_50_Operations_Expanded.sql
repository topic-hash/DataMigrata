
-- ============================================================================
-- 50 SOPHISTICATED MSSQL OPERATIONS - EXPANDED DATA EDITION
-- Compatible with MSSQL_Advanced_Demo v2.0 (5,000 employees, 5,000 transactions)
-- ============================================================================
USE MSSQL_Advanced_Demo;
GO

-- ============================================================================
-- CATEGORY 1: HIERARCHICAL & RECURSIVE QUERIES (Operations 1-5)
-- ============================================================================

-- OP 1: Recursive CTE with HIERARCHYID path building and cycle detection
WITH EmployeeHierarchy AS (
    SELECT 
        EmployeeID, ManagerID, FullName, Department, Salary, JobTitle,
        CAST(FullName AS NVARCHAR(MAX)) AS HierarchyPath,
        0 AS Level,
        CAST(EmployeeID AS VARCHAR(MAX)) AS PathString,
        Salary AS CumulativeSalary
    FROM HR.Employees
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT 
        e.EmployeeID, e.ManagerID, e.FullName, e.Department, e.Salary, e.JobTitle,
        CAST(h.HierarchyPath + ' > ' + e.FullName AS NVARCHAR(MAX)),
        h.Level + 1,
        CAST(h.PathString + '.' + CAST(e.EmployeeID AS VARCHAR) AS VARCHAR(MAX)),
        h.CumulativeSalary + e.Salary
    FROM HR.Employees e
    INNER JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10
)
SELECT TOP 100
    EmployeeID, FullName, Department, JobTitle, Salary, Level,
    HierarchyPath,
    CumulativeSalary,
    REPLICATE('  ', Level) + FullName AS IndentedDisplay
FROM EmployeeHierarchy
ORDER BY PathString
OPTION (MAXRECURSION 100);
GO

-- OP 2: Recursive CTE with aggregation up the hierarchy
WITH HierarchyAgg AS (
    SELECT EmployeeID, ManagerID, FullName, Salary, 1 AS SubordinateCount
    FROM HR.Employees
    WHERE EmployeeID NOT IN (SELECT ManagerID FROM HR.Employees WHERE ManagerID IS NOT NULL)
    UNION ALL
    SELECT 
        p.EmployeeID, p.ManagerID, p.FullName, p.Salary,
        c.SubordinateCount + ISNULL((SELECT COUNT(*) FROM HR.Employees s WHERE s.ManagerID = p.EmployeeID), 0)
    FROM HR.Employees p
    INNER JOIN HierarchyAgg c ON c.ManagerID = p.EmployeeID
)
SELECT TOP 50
    e.EmployeeID, e.FullName, e.Department, e.JobTitle, e.Salary,
    ISNULL(a.SubordinateCount, 0) AS TotalSubordinates,
    e.Salary + ISNULL((SELECT SUM(Salary) FROM HR.Employees WHERE ManagerID = e.EmployeeID), 0) AS TeamCost
FROM HR.Employees e
LEFT JOIN HierarchyAgg a ON e.EmployeeID = a.EmployeeID
ORDER BY TeamCost DESC;
GO

-- OP 3: HIERARCHYID data type for optimized tree operations
SELECT TOP 100
    o.OrgNode.ToString() AS Path,
    o.OrgLevel,
    e.FullName,
    e.JobTitle,
    o.PositionTitle,
    o.OrgNode.GetAncestor(1).ToString() AS ParentPath,
    o.OrgNode.IsDescendantOf(HIERARCHYID::Parse('/')) AS IsUnderRoot
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrgNode;
GO

-- OP 4: Recursive CTE with path enumeration and string aggregation
WITH OrgPath AS (
    SELECT EmployeeID, ManagerID, FullName, 
           CAST(FullName AS NVARCHAR(MAX)) AS Path,
           CAST(CAST(EmployeeID AS VARCHAR(10)) AS VARCHAR(MAX)) AS IdPath
    FROM HR.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FullName,
           p.Path + ' -> ' + e.FullName,
           p.IdPath + ',' + CAST(e.EmployeeID AS VARCHAR(10))
    FROM HR.Employees e
    JOIN OrgPath p ON e.ManagerID = p.EmployeeID
)
SELECT TOP 100 EmployeeID, FullName, Path, IdPath,
       LEN(IdPath) - LEN(REPLACE(IdPath, ',', '')) + 1 AS Depth
FROM OrgPath
ORDER BY IdPath;
GO

-- OP 5: Closure table pattern using recursive CTE for transitive relationships
WITH TransitiveClosure AS (
    SELECT ManagerID AS Ancestor, EmployeeID AS Descendant, 1 AS Distance
    FROM HR.Employees WHERE ManagerID IS NOT NULL
    UNION ALL
    SELECT tc.Ancestor, e.EmployeeID, tc.Distance + 1
    FROM TransitiveClosure tc
    JOIN HR.Employees e ON tc.Descendant = e.ManagerID
)
SELECT TOP 100
    a.FullName AS Manager,
    d.FullName AS Subordinate,
    d.Department,
    tc.Distance,
    CASE WHEN tc.Distance = 1 THEN 'Direct' ELSE 'Indirect' END AS Relationship
FROM TransitiveClosure tc
JOIN HR.Employees a ON tc.Ancestor = a.EmployeeID
JOIN HR.Employees d ON tc.Descendant = d.EmployeeID
ORDER BY tc.Ancestor, tc.Distance;
GO

-- ============================================================================
-- CATEGORY 2: XML OPERATIONS (Operations 6-10)
-- ============================================================================

-- OP 6: XML data modification using modify() method with XML DML
UPDATE TOP (10) HR.Employees
SET EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill> 
                         into (/Employee/Skills)[1]')
WHERE EmployeeData IS NOT NULL;

SELECT TOP 20 EmployeeID, FullName, EmployeeData.query('/Employee/Skills/Skill') AS Skills
FROM HR.Employees WHERE EmployeeData IS NOT NULL;
GO

-- OP 7: XML shredding with nodes() method and cross apply
SELECT TOP 50
    e.EmployeeID,
    e.FullName,
    skill.value('@level', 'NVARCHAR(20)') AS SkillLevel,
    skill.value('.', 'NVARCHAR(100)') AS SkillName
FROM HR.Employees e
CROSS APPLY e.EmployeeData.nodes('/Employee/Skills/Skill') AS Skills(skill)
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel;
GO

-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
SELECT TOP 20
    EmployeeID,
    FullName,
    (SELECT 
        Skill.value('.', 'NVARCHAR(100)') AS '@name',
        Skill.value('@level', 'NVARCHAR(20)') AS '@level'
     FROM HR.Employees e2
     CROSS APPLY e2.EmployeeData.nodes('/Employee/Skills/Skill') AS S(Skill)
     WHERE e2.EmployeeID = e.EmployeeID
     FOR XML PATH('Skill'), ROOT('Skills'), TYPE
    ) AS SkillsXML
FROM HR.Employees e
WHERE EmployeeData IS NOT NULL;
GO

-- OP 9: XML index optimization demonstration
-- (Indexes created during migration, query leverages them)
SELECT TOP 50 EmployeeID, FullName, Department
FROM HR.Employees
WHERE EmployeeData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1;
GO

-- OP 10: Typed XML with XML Schema Collections
-- (Schema collection created during migration)
DECLARE @typed XML;
SET @typed = '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>';
SELECT @typed.query('/Employee/Skills/Skill[@level="Expert"]');
GO

-- ============================================================================
-- CATEGORY 3: JSON OPERATIONS (Operations 11-15)
-- ============================================================================

-- OP 11: JSON path queries with lax/strict modes
SELECT TOP 50
    TransactionID,
    JSON_VALUE(TransactionDetails, '$.payment_method') AS PaymentMethod,
    JSON_VALUE(TransactionDetails, '$.terms') AS Terms,
    JSON_QUERY(TransactionDetails, '$.discount_code') AS DiscountInfo,
    ISNULL(JSON_VALUE(TransactionDetails, '$.po_number'), 'N/A') AS PONumber,
    JSON_VALUE(TransactionDetails, '$.currency') AS Currency
FROM Sales.Transactions;
GO

-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
SELECT TOP 10
    e.Department,
    e.FullName AS EmployeeName,
    (SELECT 
        t.TransactionID,
        t.TotalAmount,
        t.TransactionDate,
        JSON_VALUE(t.TransactionDetails, '$.payment_method') AS PaymentMethod
     FROM Sales.Transactions t
     WHERE t.EmployeeID = e.EmployeeID
     FOR JSON PATH
    ) AS TransactionsJSON
FROM HR.Employees e
WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Sales.Transactions)
FOR JSON PATH, ROOT('SalesReport');
GO

-- OP 13: JSON data modification with JSON_MODIFY
UPDATE TOP (100) Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, '$.processed', CAST(1 AS BIT))
WHERE JSON_VALUE(TransactionDetails, '$.processed') IS NULL;

UPDATE TOP (50) Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, 'append $.tags', 'high_value')
WHERE TotalAmount > 50000;

SELECT TOP 20 TransactionID, TotalAmount, TransactionDetails FROM Sales.Transactions;
GO

-- OP 14: OpenJSON with explicit schema for table-valued parsing
SELECT TOP 20 *
FROM OPENJSON((SELECT TOP 1 TransactionDetails FROM Sales.Transactions WHERE TransactionDetails IS NOT NULL))
WITH (
    payment_method NVARCHAR(50) '$.payment_method',
    terms NVARCHAR(20) '$.terms',
    discount_code NVARCHAR(50) '$.discount_code',
    po_number NVARCHAR(50) '$.po_number',
    processed BIT '$.processed'
);
GO

-- OP 15: JSON array aggregation and decomposition
DECLARE @orders NVARCHAR(MAX) = '[
    {"product": "Server", "qty": 2, "price": 49999.99},
    {"product": "Agent", "qty": 5, "price": 4999.99}
]';

SELECT *
FROM OPENJSON(@orders)
WITH (
    Product NVARCHAR(100) '$.product',
    Quantity INT '$.qty',
    Price DECIMAL(18,2) '$.price',
    LineTotal AS (Quantity * Price)
);
GO

-- ============================================================================
-- CATEGORY 4: TEMPORAL TABLES (Operations 16-20)
-- ============================================================================

-- OP 16: Temporal querying - AS OF
SELECT TOP 50
    TransactionID, EmployeeID, TotalAmount, TransactionDate,
    ValidFrom, ValidTo
FROM Sales.Transactions
FOR SYSTEM_TIME AS OF DATEADD(DAY, -1, SYSUTCDATETIME())
ORDER BY TransactionID;
GO

-- OP 17: Temporal querying - BETWEEN
SELECT TOP 50
    TransactionID, TotalAmount, ValidFrom, ValidTo,
    CASE 
        WHEN ValidTo = '9999-12-31 23:59:59.9999999' THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM Sales.Transactions
FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-12-31'
ORDER BY TransactionID, ValidFrom;
GO

-- OP 18: Temporal querying - CONTAINED IN
SELECT TOP 50
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    DATEDIFF(SECOND, h.ValidFrom, h.ValidTo) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.9999999'
ORDER BY h.ValidFrom DESC;
GO

-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
DECLARE @PointInTime DATETIME2 = DATEADD(HOUR, -2, SYSUTCDATETIME());

SELECT TOP 20
    t.TransactionID,
    t.TotalAmount AS CurrentAmount,
    (SELECT TOP 1 h.TotalAmount 
     FROM Sales.TransactionsHistory h 
     WHERE h.TransactionID = t.TransactionID 
     AND h.ValidFrom <= @PointInTime
     ORDER BY h.ValidFrom DESC) AS AmountAtPointInTime
FROM Sales.Transactions t;
GO

-- OP 20: Temporal table with versioning analytics
SELECT TOP 50
    TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    DATEDIFF(DAY, MIN(ValidFrom), MAX(ValidFrom)) AS LifespanDays
FROM Sales.Transactions FOR SYSTEM_TIME ALL
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY VersionCount DESC;
GO

-- ============================================================================
-- CATEGORY 5: ADVANCED VIEWS (Operations 21-30)
-- ============================================================================

-- OP 21: Indexed (Materialized) View with SCHEMABINDING and aggregation
-- Already created during migration; query it directly
SELECT * FROM Sales.vw_ProductSummary WITH (NOEXPAND)
ORDER BY Category;
GO

-- OP 22: Partitioned View across multiple tables
SELECT TOP 50 * FROM Sales.vw_AllTransactions 
WHERE TransactionDate >= '2025-01-01'
ORDER BY TransactionDate DESC;
GO

-- OP 23: View with CHECK OPTION for data integrity
-- vw_ActiveEmployees created during migration
SELECT TOP 50 * FROM HR.vw_ActiveEmployees
ORDER BY HireDate DESC;
GO

-- OP 24: View with INSTEAD OF triggers for updatable complex views
-- vw_TransactionSummary and trigger created during migration
SELECT TOP 50 * FROM Sales.vw_TransactionSummary
ORDER BY TransactionDate DESC;
GO

-- OP 25: Inline Table-Valued Function (parameterized view equivalent)
SELECT TOP 50 * FROM Sales.fn_GetEmployeeSales(6, '2026-01-01', '2026-12-31')
ORDER BY TransactionDate;
GO

-- OP 26: View with PIVOT for cross-tabulation
SELECT * FROM Sales.vw_EmployeeQuarterlySales
ORDER BY EmployeeID;
GO

-- OP 27: View with UNPIVOT for normalization
SELECT TOP 50 * FROM Sales.vw_NormalizedQuarterlySales 
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter;
GO

-- OP 28: View with CROSS APPLY and recursive TVF
SELECT TOP 100 * FROM HR.vw_ManagerHierarchy 
ORDER BY ManagerID, Level;
GO

-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
SELECT TOP 100 * FROM Sales.vw_MultiDimensionalSales 
ORDER BY GroupingLevel, Department, Employee;
GO

-- OP 30: View with window functions and framing
SELECT TOP 100 * FROM Sales.vw_RunningTotalsAndRanks 
ORDER BY FullName, TransactionDate;
GO

-- ============================================================================
-- CATEGORY 6: SPATIAL DATA (Operations 31-35)
-- ============================================================================

-- OP 31: Geography spatial queries with SRID awareness
SELECT TOP 50
    t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    t1.Region.STDistance(t2.Region) / 1000 AS DistanceKm,
    t1.Region.STAsText() AS FromLocation,
    t2.Region.STAsText() AS ToLocation
FROM Sales.Transactions t1
CROSS JOIN Sales.Transactions t2
WHERE t1.TransactionID < t2.TransactionID
AND t1.Region.STDistance(t2.Region) IS NOT NULL
ORDER BY DistanceKm;
GO

-- OP 32: Spatial buffer and intersection calculations
DECLARE @nyc GEOGRAPHY = geography::Point(40.7128, -74.0060, 4326);
DECLARE @bufferRadius INT = 5000000;

SELECT TOP 50
    TransactionID,
    TotalAmount,
    Region.Lat AS Latitude,
    Region.Long AS Longitude,
    Region.STDistance(@nyc) / 1000 AS DistanceFromNYCKm,
    CASE WHEN @nyc.STBuffer(@bufferRadius).STIntersects(Region) = 1 THEN 'Within Range' ELSE 'Outside Range' END AS Proximity
FROM Sales.Transactions
WHERE Region IS NOT NULL;
GO

-- OP 33: Geometry collections and complex spatial objects
DECLARE @route GEOGRAPHY = geography::STGeomFromText(
    'LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)', 4326);

SELECT 
    @route.STLength() / 1000 AS RouteLengthKm,
    @route.STNumPoints() AS NumberOfPoints,
    @route.STPointN(2).STAsText() AS SecondPoint;
GO

-- OP 34: Spatial index query optimization
SELECT TOP 50 TransactionID, TotalAmount
FROM Sales.Transactions WITH(INDEX(SIDX_Transactions_Region))
WHERE Region.STDistance(geography::Point(40.7128, -74.0060, 4326)) <= 10000000;
GO

-- OP 35: Multi-polygon territory analysis
DECLARE @salesTerritory GEOGRAPHY = geography::STGeomFromText(
    'MULTIPOLYGON(((-125 25, -125 50, -100 50, -100 25, -125 25)), 
                  ((-100 30, -100 45, -80 45, -80 30, -100 30)))', 4326);

SELECT TOP 50
    t.TransactionID,
    t.TotalAmount,
    @salesTerritory.STContains(t.Region) AS IsInTerritory
FROM Sales.Transactions t
WHERE t.Region IS NOT NULL;
GO

-- ============================================================================
-- CATEGORY 7: COLUMNSTORE & IN-MEMORY (Operations 36-40)
-- ============================================================================

-- OP 36: Columnstore index for analytical workloads
SELECT TOP 50
    EmployeeID,
    SUM(TotalAmount) AS TotalSales,
    AVG(TotalAmount) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC;
GO

-- OP 37: Natively compiled stored procedure
EXEC Sales.usp_GetCustomerCache;
GO

-- OP 38: Memory-optimized table with hash index
SELECT TOP 50 * FROM Sales.HighSpeedLookup 
WHERE LookupKey BETWEEN 100 AND 200
ORDER BY LookupKey;
GO

-- OP 39: Real-time operational analytics with columnstore
SELECT TOP 50 Year, SUM(Amount) AS YearTotal, COUNT(*) AS TransactionCount
FROM Archive.OldTransactions 
GROUP BY Year 
ORDER BY Year;
GO

-- OP 40: Batch mode on rowstore
SELECT TOP 50
    t.EmployeeID,
    e.FullName,
    SUM(t.TotalAmount) AS TotalSales,
    COUNT(*) OVER (PARTITION BY t.EmployeeID) AS EmployeeTransactionCount
FROM Sales.Transactions t
JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
GROUP BY t.EmployeeID, e.FullName
ORDER BY TotalSales DESC
OPTION (USE HINT('ALLOW_BATCH_MODE'));
GO

-- ============================================================================
-- CATEGORY 8: SECURITY & ENCRYPTION (Operations 41-45)
-- ============================================================================

-- OP 41: Always Encrypted with secure enclaves pattern
OPEN SYMMETRIC KEY EmployeeSymKey
    DECRYPTION BY CERTIFICATE EmployeeDataCert;

SELECT TOP 50
    s.DataID,
    e.FullName,
    CONVERT(VARCHAR, DecryptByKey(s.SSN)) AS DecryptedSSN,
    CONVERT(VARCHAR, DecryptByKey(s.CreditCard)) AS DecryptedCard,
    CONVERT(VARCHAR, DecryptByKey(s.SalaryEncrypted)) AS DecryptedSalary,
    '****-**-' + RIGHT(CONVERT(VARCHAR, DecryptByKey(s.SSN)), 4) AS MaskedSSN
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID;

CLOSE SYMMETRIC KEY EmployeeSymKey;
GO

-- OP 42: Row-Level Security (RLS) with predicate functions
-- Set session context first
EXEC sp_set_session_context 'UserEmployeeID', 4;

SELECT TOP 50 EmployeeID, FullName, Department, Salary 
FROM HR.Employees;
GO

-- OP 43: Dynamic Data Masking
-- (Masking applied during migration; query shows masked values for non-privileged users)
SELECT TOP 50 EmployeeID, FullName, Email, Salary 
FROM HR.Employees;
GO

-- OP 44: Audit specification for compliance
-- (Audit created during migration; query the audit file if configured)
SELECT TOP 50 * FROM sys.server_audits;
GO

-- OP 45: Certificate-based signing for stored procedures
-- (Procedure signed during migration)
EXEC HR.usp_GetSensitiveEmployeeData;
GO

-- ============================================================================
-- CATEGORY 9: ADVANCED PROGRAMMABILITY (Operations 46-50)
-- ============================================================================

-- OP 46: Table-valued parameters for bulk operations
DECLARE @items Sales.OrderItemType;
INSERT INTO @items VALUES (1, 2, 49999.99, 0), (3, 5, 4999.99, 0.1);
EXEC Sales.usp_BulkInsertOrders @items, 6, 999;
GO

-- OP 47: MERGE statement with OUTPUT clause and $action
MERGE Sales.Products AS target
USING (VALUES 
    (1, 'Quantum Database Server Enterprise v2', 'Software', 54999.99),
    (1001, 'New AI Module 2026', 'Software', 9999.99)
) AS source (ProductID, ProductName, Category, BasePrice)
ON target.ProductID = source.ProductID
WHEN MATCHED THEN
    UPDATE SET ProductName = source.ProductName, BasePrice = source.BasePrice
WHEN NOT MATCHED THEN
    INSERT (ProductName, Category, BasePrice) 
    VALUES (source.ProductName, source.Category, source.BasePrice)
OUTPUT 
    $action AS ActionTaken,
    INSERTED.ProductID,
    INSERTED.ProductName AS NewName,
    DELETED.ProductName AS OldName,
    INSERTED.BasePrice AS NewPrice,
    DELETED.BasePrice AS OldPrice;
GO

-- OP 48: TRY_CONVERT with error handling for data type conversion
SELECT TOP 50
    TransactionID,
    TRY_CONVERT(INT, JSON_VALUE(TransactionDetails, '$.seats')) AS ParsedSeats,
    TRY_CONVERT(DECIMAL(18,2), JSON_VALUE(TransactionDetails, '$.discount_amount')) AS ParsedDiscount,
    TRY_CAST(JSON_VALUE(TransactionDetails, '$.processed') AS BIT) AS IsProcessed,
    IIF(TRY_CONVERT(INT, JSON_VALUE(TransactionDetails, '$.seats')) IS NULL, 'Invalid', 'Valid') AS ConversionStatus
FROM Sales.Transactions;
GO

-- OP 49: SESSION_CONTEXT for cross-request state
EXEC sp_set_session_context 'UserEmployeeID', 4;
EXEC sp_set_session_context 'Department', 'Engineering';
EXEC sp_set_session_context 'SecurityLevel', 3;

SELECT 
    SESSION_CONTEXT(N'UserEmployeeID') AS CurrentUserID,
    SESSION_CONTEXT(N'Department') AS CurrentDept,
    SESSION_CONTEXT(N'SecurityLevel') AS CurrentSecLevel,
    SUSER_SNAME() AS ServerLogin,
    ORIGINAL_LOGIN() AS OriginalLogin,
    APP_NAME() AS ApplicationName;
GO

-- OP 50: System-versioned temporal with CHANGETABLE
-- Query change tracking information
SELECT TOP 50
    CT.ProductID,
    CT.SYS_CHANGE_VERSION AS ChangeVersion,
    CT.SYS_CHANGE_OPERATION AS Operation,
    p.ProductName,
    p.BasePrice
FROM CHANGETABLE(CHANGES Sales.Products, 0) CT
LEFT JOIN Sales.Products p ON CT.ProductID = p.ProductID;
GO

-- ============================================================================
-- BONUS: QUERY STORE ANALYSIS (MSSQL Unique Monitoring)
-- ============================================================================
SELECT TOP 50
    qsq.query_id,
    qsq.query_hash,
    qsrs.count_executions,
    qsrs.avg_duration / 1000.0 AS AvgDurationMs,
    qsrs.avg_cpu_time / 1000.0 AS AvgCpuMs,
    qsrs.avg_logical_io_reads AS AvgReads,
    qsrs.last_execution_time
FROM sys.query_store_query qsq
JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
WHERE qsrs.last_execution_time > DATEADD(DAY, -1, GETDATE())
ORDER BY qsrs.avg_duration DESC;
GO

-- ============================================================================
-- BONUS: PARTITION METADATA QUERY
-- ============================================================================
SELECT 
    OBJECT_NAME(p.object_id) AS TableName,
    p.partition_number,
    prv.value AS BoundaryValue,
    p.rows AS RowCount
FROM sys.partitions p
JOIN sys.partition_schemes ps ON p.data_space_id = ps.data_space_id
JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
LEFT JOIN sys.partition_range_values prv ON pf.function_id = prv.function_id 
    AND p.partition_number = prv.boundary_id + 1
WHERE p.object_id = OBJECT_ID('Sales.PartitionedSales')
AND p.index_id IN (0, 1)
ORDER BY p.partition_number;
GO

PRINT '============================================================';
PRINT 'ALL 50 SOPHISTICATED MSSQL OPERATIONS EXECUTED SUCCESSFULLY';
PRINT '============================================================';
GO
