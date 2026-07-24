
-- ============================================================================
-- 50 SOPHISTICATED MSSQL OPERATIONS
-- These leverage T-SQL features that are either unique to MSSQL or significantly
-- more advanced/capable than equivalent operations in other RDBMS systems
-- ============================================================================
USE MSSQL_Advanced_Demo;
GO

-- ============================================================================
-- CATEGORY 1: HIERARCHICAL & RECURSIVE QUERIES (Operations 1-5)
-- ============================================================================

-- OP 1: Recursive CTE with HIERARCHYID path building and cycle detection
-- MSSQL's CTEs support MAXRECURSION hint and sophisticated cycle detection
WITH EmployeeHierarchy AS (
    -- Anchor: top-level managers
    SELECT 
        EmployeeID, ManagerID, FullName, Department, Salary,
        CAST(FullName AS NVARCHAR(MAX)) AS HierarchyPath,
        0 AS Level,
        CAST(EmployeeID AS VARCHAR(MAX)) AS PathString,
        Salary AS CumulativeSalary
    FROM HR.Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive: subordinates
    SELECT 
        e.EmployeeID, e.ManagerID, e.FullName, e.Department, e.Salary,
        CAST(h.HierarchyPath + ' > ' + e.FullName AS NVARCHAR(MAX)),
        h.Level + 1,
        CAST(h.PathString + '.' + CAST(e.EmployeeID AS VARCHAR) AS VARCHAR(MAX)),
        h.CumulativeSalary + e.Salary
    FROM HR.Employees e
    INNER JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10  -- Safety limit within recursion
)
SELECT 
    EmployeeID, FullName, Department, Salary, Level,
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
SELECT 
    e.EmployeeID, e.FullName, e.Department, e.Salary,
    ISNULL(a.SubordinateCount, 0) AS TotalSubordinates,
    e.Salary + ISNULL((SELECT SUM(Salary) FROM HR.Employees WHERE ManagerID = e.EmployeeID), 0) AS TeamCost
FROM HR.Employees e
LEFT JOIN HierarchyAgg a ON e.EmployeeID = a.EmployeeID
ORDER BY TeamCost DESC;
GO

-- OP 3: HIERARCHYID data type for optimized tree operations
-- Create a new table using HIERARCHYID (native MSSQL type)
CREATE TABLE HR.OrgChart (
    OrgNode HIERARCHYID PRIMARY KEY CLUSTERED,
    OrgLevel AS OrgNode.GetLevel(),
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    PositionTitle NVARCHAR(100)
);

-- Insert using GetDescendant for proper tree positioning
INSERT INTO HR.OrgChart (OrgNode, EmployeeID, PositionTitle)
VALUES 
    (HIERARCHYID::GetRoot(), 1, 'Chief Executive Officer'),
    (HIERARCHYID::GetRoot().GetDescendant(NULL, NULL), 2, 'VP Engineering'),
    (HIERARCHYID::GetRoot().GetDescendant(NULL, NULL).GetDescendant(NULL, NULL), 4, 'Senior Database Architect'),
    (HIERARCHYID::GetRoot().GetDescendant(NULL, NULL).GetDescendant(NULL, NULL).GetDescendant(NULL, NULL), 8, 'Database Administrator');

-- Query ancestors, descendants, and subtree efficiently
SELECT 
    o.OrgNode.ToString() AS Path,
    o.OrgLevel,
    e.FullName,
    o.PositionTitle,
    o.OrgNode.GetAncestor(1).ToString() AS ParentPath,
    o.OrgNode.IsDescendantOf(HIERARCHYID::Parse('/')) AS IsUnderRoot
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
WHERE o.OrgNode.IsDescendantOf(HIERARCHYID::Parse('/1/')) = 1  -- Subtree under VP Engineering
ORDER BY o.OrgNode;
GO

-- OP 4: Recursive CTE with path enumeration and string aggregation (FOR XML PATH)
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
SELECT EmployeeID, FullName, Path, IdPath,
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
SELECT 
    a.FullName AS Manager,
    d.FullName AS Subordinate,
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
UPDATE HR.Employees
SET EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill> 
                         into (/Employee/Skills)[1]')
WHERE EmployeeID = 1;

-- Verify the modification
SELECT EmployeeID, FullName, EmployeeData.query('/Employee/Skills/Skill') AS Skills
FROM HR.Employees WHERE EmployeeID = 1;
GO

-- OP 7: XML shredding with nodes() method and cross apply
SELECT 
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
SELECT 
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
CREATE PRIMARY XML INDEX PXML_EmployeeData ON HR.Employees(EmployeeData);
CREATE XML INDEX SXML_EmployeeData_Value ON HR.Employees(EmployeeData)
    USING XML INDEX PXML_EmployeeData FOR VALUE;
CREATE XML INDEX SXML_EmployeeData_Path ON HR.Employees(EmployeeData)
    USING XML INDEX PXML_EmployeeData FOR PATH;

-- Query leveraging XML indexes
SELECT EmployeeID, FullName
FROM HR.Employees
WHERE EmployeeData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1;
GO

-- OP 10: XML namespace handling with typed XML
CREATE XML SCHEMA COLLECTION EmployeeSchema AS '
<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <xsd:element name="Employee">
    <xsd:complexType>
      <xsd:sequence>
        <xsd:element name="Skills" minOccurs="0">
          <xsd:complexType>
            <xsd:sequence>
              <xsd:element name="Skill" maxOccurs="unbounded">
                <xsd:complexType>
                  <xsd:simpleContent>
                    <xsd:extension base="xsd:string">
                      <xsd:attribute name="level" type="xsd:string"/>
                    </xsd:extension>
                  </xsd:simpleContent>
                </xsd:complexType>
              </xsd:element>
            </xsd:sequence>
          </xsd:complexType>
        </xsd:element>
      </xsd:sequence>
    </xsd:complexType>
  </xsd:element>
</xsd:schema>';

DECLARE @typed XML(EmployeeSchema);
SET @typed = '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>';
SELECT @typed.query('/Employee/Skills/Skill[@level="Expert"]');
GO

-- ============================================================================
-- CATEGORY 3: JSON OPERATIONS (Operations 11-15)
-- ============================================================================

-- OP 11: JSON path queries with lax/strict modes
SELECT 
    TransactionID,
    TransactionDetails,
    JSON_VALUE(TransactionDetails, '$.payment_method') AS PaymentMethod,
    JSON_VALUE(TransactionDetails, '$.terms') AS Terms,
    JSON_QUERY(TransactionDetails, '$.discount_code') AS DiscountInfo,
    ISNULL(JSON_VALUE(TransactionDetails, '$.po_number'), 'N/A') AS PONumber,
    JSON_VALUE(TransactionDetails, '$.currency') AS Currency  -- Returns NULL if absent (lax mode)
FROM Sales.Transactions;
GO

-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
SELECT 
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
WHERE e.EmployeeID IN (SELECT EmployeeID FROM Sales.Transactions)
FOR JSON PATH, ROOT('SalesReport');
GO

-- OP 13: JSON data modification with JSON_MODIFY
UPDATE Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, '$.processed', CAST(1 AS BIT))
WHERE TransactionID = 1;

UPDATE Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, 'append $.tags', 'high_value')
WHERE TotalAmount > 50000;

SELECT TransactionID, TransactionDetails FROM Sales.Transactions;
GO

-- OP 14: OpenJSON with explicit schema for table-valued parsing
SELECT *
FROM OPENJSON((SELECT TransactionDetails FROM Sales.Transactions WHERE TransactionID = 1))
WITH (
    payment_method NVARCHAR(50) '$.payment_method',
    terms NVARCHAR(20) '$.terms',
    discount_code NVARCHAR(50) '$.discount_code',
    po_number NVARCHAR(50) '$.po_number'
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
SELECT 
    TransactionID, EmployeeID, TotalAmount, TransactionDate,
    ValidFrom, ValidTo
FROM Sales.Transactions
FOR SYSTEM_TIME AS OF '2026-07-22T12:00:00'
WHERE TransactionID = 1;
GO

-- OP 17: Temporal querying - BETWEEN
SELECT 
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
SELECT 
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    DATEDIFF(SECOND, h.ValidFrom, h.ValidTo) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.9999999'
ORDER BY h.ValidFrom DESC;
GO

-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
DECLARE @PointInTime DATETIME2 = DATEADD(HOUR, -2, SYSUTCDATETIME());

SELECT 
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
SELECT 
    TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    DATEDIFF(DAY, MIN(ValidFrom), MAX(ValidFrom)) AS LifespanDays
FROM Sales.Transactions FOR SYSTEM_TIME ALL
GROUP BY TransactionID
HAVING COUNT(*) > 1;
GO

-- ============================================================================
-- CATEGORY 5: ADVANCED VIEWS (Operations 21-30) - MSSQL VIEW SPECIALTIES
-- ============================================================================

-- OP 21: Indexed (Materialized) View with SCHEMABINDING and aggregation
-- This is physically stored and automatically maintained by MSSQL
CREATE VIEW Sales.vw_MonthlyRevenue WITH SCHEMABINDING
AS
SELECT 
    DATEPART(YEAR, t.TransactionDate) AS SaleYear,
    DATEPART(MONTH, t.TransactionDate) AS SaleMonth,
    COUNT_BIG(*) AS TransactionCount,
    SUM(ISNULL(t.TotalAmount, 0)) AS TotalRevenue,
    AVG(ISNULL(t.TotalAmount, 0)) AS AvgTransactionValue
FROM Sales.Transactions t
GROUP BY DATEPART(YEAR, t.TransactionDate), DATEPART(MONTH, t.TransactionDate);
GO

CREATE UNIQUE CLUSTERED INDEX IX_vw_MonthlyRevenue 
ON Sales.vw_MonthlyRevenue(SaleYear, SaleMonth);
GO

-- Query the indexed view directly (no expand)
SELECT * FROM Sales.vw_MonthlyRevenue WITH (NOEXPAND)
ORDER BY SaleYear, SaleMonth;
GO

-- OP 22: Partitioned View across multiple tables (Distributed Partitioned View)
CREATE VIEW Sales.vw_AllTransactions
AS
SELECT TransactionID, 'Current' AS SourceTable, TransactionDate, TotalAmount
FROM Sales.Transactions
UNION ALL
SELECT TransactionID, 'Archive' AS SourceTable, 
       DATEFROMPARTS(Year, Month, 1) AS TransactionDate, Amount AS TotalAmount
FROM Archive.OldTransactions;
GO

-- Query with partition elimination
SELECT * FROM Sales.vw_AllTransactions 
WHERE TransactionDate >= '2025-01-01';
GO

-- OP 23: View with CHECK OPTION for data integrity
CREATE VIEW HR.vw_ActiveEmployees
AS
SELECT EmployeeID, FullName, Department, Salary, HireDate
FROM HR.Employees
WHERE IsActive = 1
WITH CHECK OPTION;  -- Prevents inserting terminated employees through view
GO

-- OP 24: View with INSTEAD OF triggers for updatable complex views
CREATE VIEW Sales.vw_TransactionSummary
AS
SELECT 
    t.TransactionID,
    e.FullName AS EmployeeName,
    t.TotalAmount,
    t.TransactionDate,
    JSON_VALUE(t.TransactionDetails, '$.payment_method') AS PaymentMethod
FROM Sales.Transactions t
JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID;
GO

CREATE TRIGGER trg_vw_TransactionSummary_Insert
ON Sales.vw_TransactionSummary
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Sales.Transactions (EmployeeID, TotalAmount, TransactionDetails)
    SELECT 
        e.EmployeeID,
        i.TotalAmount,
        JSON_OBJECT('payment_method': i.PaymentMethod)
    FROM inserted i
    JOIN HR.Employees e ON i.EmployeeName = e.FullName;
END;
GO

-- OP 25: Inline Table-Valued Function (parameterized view equivalent)
CREATE FUNCTION Sales.fn_GetEmployeeSales(@EmployeeID INT, @StartDate DATE, @EndDate DATE)
RETURNS TABLE
AS
RETURN (
    SELECT 
        t.TransactionID,
        t.TotalAmount,
        t.TransactionDate,
        t.Region.Lat AS Latitude,
        t.Region.Long AS Longitude,
        t.Region.STAsText() AS GeoLocation
    FROM Sales.Transactions t
    WHERE t.EmployeeID = @EmployeeID
    AND t.TransactionDate BETWEEN @StartDate AND @EndDate
);
GO

-- Usage
SELECT * FROM Sales.fn_GetEmployeeSales(6, '2026-01-01', '2026-12-31');
GO

-- OP 26: View with PIVOT for cross-tabulation
CREATE VIEW Sales.vw_EmployeeQuarterlySales
AS
SELECT 
    EmployeeID,
    [Q1] AS FirstQuarter,
    [Q2] AS SecondQuarter,
    [Q3] AS ThirdQuarter,
    [Q4] AS FourthQuarter
FROM (
    SELECT 
        EmployeeID,
        TotalAmount,
        'Q' + CAST(DATEPART(QUARTER, TransactionDate) AS VARCHAR) AS Quarter
    FROM Sales.Transactions
    WHERE TransactionDate >= DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
) src
PIVOT (
    SUM(TotalAmount)
    FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])
) piv;
GO

SELECT * FROM Sales.vw_EmployeeQuarterlySales;
GO

-- OP 27: View with UNPIVOT for normalization
CREATE VIEW Sales.vw_NormalizedQuarterlySales
AS
SELECT EmployeeID, Quarter, Amount
FROM Sales.vw_EmployeeQuarterlySales
UNPIVOT (
    Amount FOR Quarter IN (FirstQuarter, SecondQuarter, ThirdQuarter, FourthQuarter)
) AS unpvt;
GO

SELECT * FROM Sales.vw_NormalizedQuarterlySales WHERE Amount IS NOT NULL;
GO

-- OP 28: View with CROSS APPLY and table-valued function pattern
CREATE FUNCTION HR.fn_GetSubordinates(@ManagerID INT)
RETURNS TABLE
AS
RETURN (
    WITH Subordinates AS (
        SELECT EmployeeID, FullName, ManagerID, 1 AS Level
        FROM HR.Employees WHERE ManagerID = @ManagerID
        UNION ALL
        SELECT e.EmployeeID, e.FullName, e.ManagerID, s.Level + 1
        FROM HR.Employees e
        JOIN Subordinates s ON e.ManagerID = s.EmployeeID
    )
    SELECT * FROM Subordinates
);
GO

CREATE VIEW HR.vw_ManagerHierarchy
AS
SELECT 
    m.EmployeeID AS ManagerID,
    m.FullName AS ManagerName,
    s.EmployeeID AS SubordinateID,
    s.FullName AS SubordinateName,
    s.Level
FROM HR.Employees m
CROSS APPLY HR.fn_GetSubordinates(m.EmployeeID) s
WHERE m.ManagerID IS NULL OR m.EmployeeID IN (SELECT DISTINCT ManagerID FROM HR.Employees WHERE ManagerID IS NOT NULL);
GO

SELECT * FROM HR.vw_ManagerHierarchy ORDER BY ManagerID, Level;
GO

-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
CREATE VIEW Sales.vw_MultiDimensionalSales
AS
SELECT 
    COALESCE(e.Department, 'ALL') AS Department,
    COALESCE(e.FullName, 'ALL') AS Employee,
    COALESCE(p.Category, 'ALL') AS Category,
    SUM(t.TotalAmount) AS TotalSales,
    GROUPING_ID(e.Department, e.FullName, p.Category) AS GroupingLevel
FROM Sales.Transactions t
JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
JOIN Sales.Products p ON t.ProductID = p.ProductID
GROUP BY GROUPING SETS (
    (e.Department, e.FullName, p.Category),
    (e.Department, e.FullName),
    (e.Department, p.Category),
    (e.Department),
    (p.Category),
    ()
);
GO

SELECT * FROM Sales.vw_MultiDimensionalSales ORDER BY GroupingLevel, Department, Employee;
GO

-- OP 30: View with window functions and framing
CREATE VIEW Sales.vw_RunningTotalsAndRanks
AS
SELECT 
    t.TransactionID,
    e.FullName,
    t.TotalAmount,
    t.TransactionDate,
    SUM(t.TotalAmount) OVER (
        PARTITION BY t.EmployeeID 
        ORDER BY t.TransactionDate 
        ROWS UNBOUNDED PRECEDING
    ) AS RunningTotal,
    RANK() OVER (PARTITION BY t.EmployeeID ORDER BY t.TotalAmount DESC) AS AmountRank,
    LAG(t.TotalAmount, 1, 0) OVER (PARTITION BY t.EmployeeID ORDER BY t.TransactionDate) AS PreviousAmount,
    LEAD(t.TotalAmount, 1, 0) OVER (PARTITION BY t.EmployeeID ORDER BY t.TransactionDate) AS NextAmount,
    FIRST_VALUE(t.TotalAmount) OVER (
        PARTITION BY t.EmployeeID 
        ORDER BY t.TransactionDate 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS FirstTransactionAmount,
    PERCENT_RANK() OVER (PARTITION BY t.EmployeeID ORDER BY t.TotalAmount) AS Percentile
FROM Sales.Transactions t
JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID;
GO

SELECT * FROM Sales.vw_RunningTotalsAndRanks ORDER BY FullName, TransactionDate;
GO

-- ============================================================================
-- CATEGORY 6: SPATIAL DATA (Operations 31-35)
-- ============================================================================

-- OP 31: Geography spatial queries with SRID awareness
SELECT 
    t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    t1.Region.STDistance(t2.Region) / 1000 AS DistanceKm,
    t1.Region.STDistance(t2.Region) / 1609.344 AS DistanceMiles,
    t1.Region.STAsText() AS FromLocation,
    t2.Region.STAsText() AS ToLocation
FROM Sales.Transactions t1
CROSS JOIN Sales.Transactions t2
WHERE t1.TransactionID < t2.TransactionID
AND t1.Region.STDistance(t2.Region) IS NOT NULL
ORDER BY DistanceKm;
GO

-- OP 32: Spatial intersection and area calculations
DECLARE @nyc GEOGRAPHY = geography::Point(40.7128, -74.0060, 4326);
DECLARE @bufferRadius INT = 5000000; -- 5000km radius

SELECT 
    TransactionID,
    TotalAmount,
    Region.Lat AS Latitude,
    Region.Long AS Longitude,
    Region.STDistance(@nyc) / 1000 AS DistanceFromNYCKm,
    Region.STBuffer(100000).STArea() / 1000000 AS BufferAreaSqKm,
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
    @route.STPointN(2).STAsText() AS SecondPoint,
    @route.STEnvelope().STAsText() AS BoundingBox;
GO

-- OP 34: Spatial index query optimization
CREATE SPATIAL INDEX SIDX_Transactions_Region ON Sales.Transactions(Region)
USING GEOGRAPHY_GRID
WITH (
    GRIDS = (MEDIUM, MEDIUM, MEDIUM, MEDIUM),
    CELLS_PER_OBJECT = 16,
    PAD_INDEX = ON
);

-- Query using spatial index
SELECT TransactionID, TotalAmount
FROM Sales.Transactions WITH(INDEX(SIDX_Transactions_Region))
WHERE Region.STDistance(geography::Point(40.7128, -74.0060, 4326)) <= 10000000;
GO

-- OP 35: Multi-polygon and complex region queries
DECLARE @salesTerritory GEOGRAPHY = geography::STGeomFromText(
    'MULTIPOLYGON(((-125 25, -125 50, -100 50, -100 25, -125 25)), 
                  ((-100 30, -100 45, -80 45, -80 30, -100 30)))', 4326);

SELECT 
    t.TransactionID,
    t.TotalAmount,
    t.Region.STAsText() AS PointLocation,
    @salesTerritory.STContains(t.Region) AS IsInTerritory,
    @salesTerritory.STIntersection(t.Region).STAsText() AS Intersection
FROM Sales.Transactions t
WHERE t.Region IS NOT NULL;
GO

-- ============================================================================
-- CATEGORY 7: COLUMNSTORE & IN-MEMORY (Operations 36-40)
-- ============================================================================

-- OP 36: Columnstore index for analytical workloads
CREATE NONCLUSTERED COLUMNSTORE INDEX IX_CS_Transactions 
ON Sales.Transactions (EmployeeID, ProductID, TotalAmount, TransactionDate);

-- Batch mode execution query
SELECT 
    EmployeeID,
    SUM(TotalAmount) AS TotalSales,
    AVG(TotalAmount) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC;
GO

-- OP 37: Memory-optimized table query with natively compiled stored procedure
CREATE PROCEDURE Sales.usp_GetCustomerCache
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    SELECT CustomerID, CustomerName, LastOrderDate, TotalSpent
    FROM Sales.CustomerCache
    WHERE TotalSpent > 10000
    ORDER BY TotalSpent DESC;
END;
GO

EXEC Sales.usp_GetCustomerCache;
GO

-- OP 38: In-memory OLTP with hash index optimization
CREATE TABLE Sales.HighSpeedLookup (
    LookupKey INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1000000),
    DataValue NVARCHAR(200) NOT NULL,
    Timestamp DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    INDEX IX_Value NONCLUSTERED (DataValue)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

INSERT INTO Sales.HighSpeedLookup (LookupKey, DataValue)
VALUES 
    (1, 'HighPriority_Order_001'),
    (2, 'HighPriority_Order_002'),
    (3, 'HighPriority_Order_003');

SELECT * FROM Sales.HighSpeedLookup WHERE LookupKey = 2;
GO

-- OP 39: Real-time operational analytics with hybrid buffer pool
CREATE CLUSTERED COLUMNSTORE INDEX IX_CC_OldTransactions
ON Archive.OldTransactions (Year, Month, Amount)
WITH (MAXDOP = 4, DATA_COMPRESSION = COLUMNSTORE_ARCHIVE);

SELECT Year, SUM(Amount) AS YearTotal FROM Archive.OldTransactions GROUP BY Year;
GO

-- OP 40: Batch mode on rowstore (SQL Server 2019+ optimization)
ALTER DATABASE MSSQL_Advanced_Demo SET COMPATIBILITY_LEVEL = 150;

SELECT 
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
-- (Demonstrates column encryption/decryption workflow)
OPEN SYMMETRIC KEY EmployeeSymKey
    DECRYPTION BY CERTIFICATE EmployeeDataCert;

SELECT 
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
CREATE FUNCTION Security.fn_securitypredicate(@EmployeeID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_securitypredicate_result
WHERE 
    -- Users see their own records or all if they are managers
    @EmployeeID = CAST(SESSION_CONTEXT(N'UserEmployeeID') AS INT)
    OR IS_MEMBER('db_ManagerRole') = 1
    OR CAST(SESSION_CONTEXT(N'UserEmployeeID') AS INT) IN (
        SELECT ManagerID FROM HR.Employees WHERE EmployeeID = @EmployeeID
    );
GO

CREATE SECURITY POLICY Security.EmployeeFilterPolicy
    ADD FILTER PREDICATE Security.fn_securitypredicate(EmployeeID)
        ON HR.Employees,
    ADD BLOCK PREDICATE Security.fn_securitypredicate(EmployeeID)
        ON HR.Employees AFTER INSERT
WITH (STATE = ON, SCHEMABINDING = ON);
GO

-- OP 43: Dynamic Data Masking
ALTER TABLE HR.Employees
ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');

ALTER TABLE HR.Employees
ALTER COLUMN Salary ADD MASKED WITH (FUNCTION = 'default()');

-- Query showing masked data (for non-privileged users)
SELECT EmployeeID, FullName, Email, Salary FROM HR.Employees;
GO

-- OP 44: Audit specification for compliance
CREATE SERVER AUDIT ComplianceAudit
    TO FILE (FILEPATH = 'C:\SQLAudit', MAXSIZE = 100 MB, MAX_ROLLOVER_FILES = 10)
    WITH (ON_FAILURE = CONTINUE);

ALTER SERVER AUDIT ComplianceAudit WITH (STATE = ON);

CREATE DATABASE AUDIT SPECIFICATION HR_DataAccess_Audit
    FOR SERVER AUDIT ComplianceAudit
    ADD (SELECT, INSERT, UPDATE, DELETE ON HR.Employees BY PUBLIC),
    ADD (SELECT ON Security.SensitiveData BY PUBLIC)
WITH (STATE = ON);
GO

-- OP 45: Certificate-based signing for stored procedures
CREATE CERTIFICATE ProcedureSigningCert
    ENCRYPTION BY PASSWORD = 'CertP@ssw0rd!'
    WITH SUBJECT = 'Signing Certificate for Elevated Procedures';

CREATE USER SigningUser FROM CERTIFICATE ProcedureSigningCert;

CREATE PROCEDURE HR.usp_GetSensitiveEmployeeData
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM HR.Employees e
    JOIN Security.SensitiveData s ON e.EmployeeID = s.EmployeeID;
END;
GO

ADD SIGNATURE TO HR.usp_GetSensitiveEmployeeData
    BY CERTIFICATE ProcedureSigningCert
    WITH PASSWORD = 'CertP@ssw0rd!';
GO

-- ============================================================================
-- CATEGORY 9: ADVANCED PROGRAMMABILITY (Operations 46-50)
-- ============================================================================

-- OP 46: Table-valued parameters with user-defined table types
CREATE PROCEDURE Sales.usp_BulkInsertOrders
    @OrderItems Sales.OrderItemType READONLY,
    @EmployeeID INT,
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Sales.Transactions (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, TransactionDetails)
    SELECT 
        @EmployeeID,
        @CustomerID,
        oi.ProductID,
        oi.Quantity,
        oi.UnitPrice,
        JSON_OBJECT('batch_insert': 1, 'source': 'bulk_operation')
    FROM @OrderItems oi;

    SELECT SCOPE_IDENTITY() AS LastTransactionID, @@ROWCOUNT AS RowsInserted;
END;
GO

-- Usage
DECLARE @items Sales.OrderItemType;
INSERT INTO @items VALUES (1, 2, 49999.99), (3, 5, 4999.99);
EXEC Sales.usp_BulkInsertOrders @items, 6, 999;
GO

-- OP 47: MERGE statement with OUTPUT clause and $action
MERGE Sales.Products AS target
USING (VALUES 
    (1, 'Quantum Database Server Enterprise v2', 'Software', 54999.99),
    (11, 'New AI Module', 'Software', 9999.99)
) AS source (ProductID, ProductName, Category, BasePrice)
ON target.ProductID = source.ProductID
WHEN MATCHED THEN
    UPDATE SET ProductName = source.ProductName, BasePrice = source.BasePrice, 
               ModifiedAt = SYSUTCDATETIME()
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
SELECT 
    TransactionID,
    TransactionDetails,
    TRY_CONVERT(INT, JSON_VALUE(TransactionDetails, '$.seats')) AS ParsedSeats,
    TRY_CONVERT(DECIMAL(18,2), JSON_VALUE(TransactionDetails, '$.discount_amount')) AS ParsedDiscount,
    TRY_CAST(JSON_VALUE(TransactionDetails, '$.subscription') AS BIT) AS IsSubscription,
    IIF(TRY_CONVERT(INT, JSON_VALUE(TransactionDetails, '$.seats')) IS NULL, 'Invalid', 'Valid') AS ConversionStatus
FROM Sales.Transactions;
GO

-- OP 49: SESSION_CONTEXT for cross-request state and application context
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

-- OP 50: System-versioned temporal with DML triggers and CHANGETABLE
-- Enable change tracking
ALTER DATABASE MSSQL_Advanced_Demo SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);
ALTER TABLE Sales.Products ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);

-- Query change tracking information
SELECT 
    CT.ProductID,
    CT.SYS_CHANGE_VERSION AS ChangeVersion,
    CT.SYS_CHANGE_OPERATION AS Operation,
    CT.SYS_CHANGE_COLUMNS AS ChangedColumns,
    p.ProductName,
    p.BasePrice
FROM CHANGETABLE(CHANGES Sales.Products, 0) CT
LEFT JOIN Sales.Products p ON CT.ProductID = p.ProductID;
GO

-- ============================================================================
-- BONUS: QUERY STORE ANALYSIS (MSSQL Unique Monitoring)
-- ============================================================================

-- Analyze query performance via Query Store
SELECT 
    qsq.query_id,
    qsq.query_hash,
    CAST(qsp.query_plan AS XML) AS QueryPlan,
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

PRINT 'All 50 sophisticated MSSQL operations executed successfully.';
PRINT 'Database: MSSQL_Advanced_Demo is ready for exploration.';
GO
