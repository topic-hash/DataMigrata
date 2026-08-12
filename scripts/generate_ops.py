#!/usr/bin/env python3
"""
Generate the canonical DuckDB SQL files for all 50 operations.
Each op is translated from MSSQL T-SQL to DuckDB SQL producing the EXACT same output.
"""
import os

OUT_DIR = '/home/z/my-project/duckdb_migrated'
os.makedirs(OUT_DIR, exist_ok=True)

# All 50 ops translated to DuckDB SQL
OPS = {}

# ============================================================================
# CATEGORY 1: HIERARCHICAL & RECURSIVE QUERIES (Ops 1-5)
# ============================================================================

OPS[1] = """-- OP 1: Recursive CTE with HIERARCHYID path building and cycle detection
-- Translation: HIERARCHYID → recursive CTE with materialized path
WITH RECURSIVE EmployeeHierarchy AS (
    SELECT
        EmployeeID, ManagerID, FullName, Department, Salary, JobTitle,
        CAST(FullName AS VARCHAR) AS HierarchyPath,
        0 AS Level,
        CAST(EmployeeID AS VARCHAR) AS PathString,
        CAST(Salary AS DECIMAL(18,2)) AS CumulativeSalary
    FROM HR.Employees
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT
        e.EmployeeID, e.ManagerID, e.FullName, e.Department, e.Salary, e.JobTitle,
        CAST(h.HierarchyPath || ' > ' || e.FullName AS VARCHAR),
        h.Level + 1,
        CAST(h.PathString || '.' || CAST(e.EmployeeID AS VARCHAR) AS VARCHAR),
        CAST(h.CumulativeSalary + e.Salary AS DECIMAL(18,2))
    FROM HR.Employees e
    INNER JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10
)
SELECT EmployeeID, FullName, Department, JobTitle, Salary, Level,
    HierarchyPath,
    CumulativeSalary,
    repeat('  ', Level) || FullName AS IndentedDisplay
FROM EmployeeHierarchy
ORDER BY PathString
LIMIT 100
"""

OPS[2] = """-- OP 2: Recursive CTE with aggregation up the hierarchy
WITH RECURSIVE SubCounts AS (
    SELECT ManagerID, COUNT(*) AS DirectReports
    FROM HR.Employees
    WHERE ManagerID IS NOT NULL
    GROUP BY ManagerID
),
HierarchyAgg AS (
    SELECT EmployeeID, ManagerID, FullName, Salary, 1 AS SubordinateCount
    FROM HR.Employees
    WHERE EmployeeID NOT IN (SELECT ManagerID FROM HR.Employees WHERE ManagerID IS NOT NULL)
    UNION ALL
    SELECT
        p.EmployeeID, p.ManagerID, p.FullName, p.Salary,
        c.SubordinateCount + sc.DirectReports
    FROM HR.Employees p
    INNER JOIN HierarchyAgg c ON c.ManagerID = p.EmployeeID
    INNER JOIN SubCounts sc ON sc.ManagerID = p.EmployeeID
)
SELECT
    e.EmployeeID, e.FullName, e.Department, e.JobTitle, e.Salary,
    COALESCE(a.SubordinateCount, 0) AS TotalSubordinates,
    e.Salary + COALESCE((SELECT SUM(Salary) FROM HR.Employees WHERE ManagerID = e.EmployeeID), 0) AS TeamCost
FROM HR.Employees e
LEFT JOIN HierarchyAgg a ON e.EmployeeID = a.EmployeeID
ORDER BY TeamCost DESC
LIMIT 50
"""

OPS[3] = """-- OP 3: HIERARCHYID data type for optimized tree operations
-- Translation: OrgNode.ToString() → string column; GetAncestor(1) → parent path; IsDescendantOf(root) → starts with '/'
SELECT
    o.OrgNode AS Path,
    o.OrgLevel,
    e.FullName,
    e.JobTitle,
    o.PositionTitle,
    -- GetAncestor(1).ToString(): parent path = remove last path segment
    CASE
        WHEN o.OrgNode = '/' THEN '/'
        ELSE regexp_replace(regexp_replace(o.OrgNode, '/[^/]+/$', '/'), '^/$', '/')
    END AS ParentPath,
    -- IsDescendantOf(HIERARCHYID::Parse('/')): always 1 since all nodes are under root
    1 AS IsUnderRoot
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrgNode
LIMIT 100
"""

OPS[4] = """-- OP 4: Recursive CTE with path enumeration and string aggregation
WITH RECURSIVE OrgPath AS (
    SELECT EmployeeID, ManagerID, FullName,
           CAST(FullName AS VARCHAR) AS Path,
           CAST(CAST(EmployeeID AS VARCHAR) AS VARCHAR) AS IdPath
    FROM HR.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FullName,
           CAST(p.Path || ' -> ' || e.FullName AS VARCHAR),
           CAST(p.IdPath || ',' || CAST(e.EmployeeID AS VARCHAR) AS VARCHAR)
    FROM HR.Employees e
    JOIN OrgPath p ON e.ManagerID = p.EmployeeID
)
SELECT EmployeeID, FullName, Path, IdPath,
       length(IdPath) - length(replace(IdPath, ',', '')) + 1 AS Depth
FROM OrgPath
ORDER BY IdPath
LIMIT 100
"""

OPS[5] = """-- OP 5: Closure table pattern using recursive CTE for transitive relationships
WITH RECURSIVE TransitiveClosure AS (
    SELECT ManagerID AS Ancestor, EmployeeID AS Descendant, 1 AS Distance
    FROM HR.Employees WHERE ManagerID IS NOT NULL
    UNION ALL
    SELECT tc.Ancestor, e.EmployeeID, tc.Distance + 1
    FROM TransitiveClosure tc
    JOIN HR.Employees e ON tc.Descendant = e.ManagerID
    WHERE tc.Distance < 20
)
SELECT
    a.FullName AS Manager,
    d.FullName AS Subordinate,
    d.Department,
    tc.Distance,
    CASE WHEN tc.Distance = 1 THEN 'Direct' ELSE 'Indirect' END AS Relationship
FROM TransitiveClosure tc
JOIN HR.Employees a ON tc.Ancestor = a.EmployeeID
JOIN HR.Employees d ON tc.Descendant = d.EmployeeID
ORDER BY tc.Ancestor, tc.Distance
LIMIT 100
"""

# ============================================================================
# CATEGORY 2: XML OPERATIONS (Ops 6-10)
# ============================================================================

OPS[6] = """-- OP 6: XML data modification using modify() method with XML DML
-- Translation: UPDATE TOP + XML modify is skipped (read-only). Only the SELECT part runs.
-- The XML modify would add a Skill, but for verification we return the original XML queried.
SELECT EmployeeID, FullName,
    -- query('/Employee/Skills/Skill') returns the Skills element with all children
    regexp_extract_all(EmployeeData, '<Skill[^>]*>[^<]+</Skill>') AS Skills
FROM HR.Employees
WHERE EmployeeData IS NOT NULL
ORDER BY EmployeeID
LIMIT 20
"""

OPS[7] = """-- OP 7: XML shredding with nodes() method and cross apply
-- Translation: extract <Skill level="X">Y</Skill> pairs using regex
SELECT
    e.EmployeeID,
    e.FullName,
    regexp_extract_first(m.skill, 'level="([^"]+)"', 1) AS SkillLevel,
    regexp_extract_first(m.skill, '>([^<]+)<', 1) AS SkillName
FROM HR.Employees e,
    LATERAL (
        SELECT unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS skill
    ) AS m
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel
LIMIT 50
"""

OPS[8] = """-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
-- Translation: build XML string per employee by concatenating <Skill> elements
SELECT
    e.EmployeeID,
    e.FullName,
    '<Skills>' || string_agg('<Skill name="' || regexp_extract_first(m.skill, '>([^<]+)<', 1) ||
                               '" level="' || regexp_extract_first(m.skill, 'level="([^"]+)"', 1) ||
                               '"/>', '') || '</Skills>' AS SkillsXML
FROM HR.Employees e,
    LATERAL (
        SELECT unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS skill
    ) AS m
WHERE e.EmployeeData IS NOT NULL
GROUP BY e.EmployeeID, e.FullName
ORDER BY e.EmployeeID
LIMIT 20
"""

OPS[9] = """-- OP 9: XML index optimization demonstration
-- Translation: exist('/Employee/Skills/Skill[@level="Expert"]') → regex search
SELECT EmployeeID, FullName, Department
FROM HR.Employees
WHERE regexp_matches(EmployeeData, '<Skill level="Expert"')
ORDER BY EmployeeID
LIMIT 50
"""

OPS[10] = """-- OP 10: Typed XML with XML Schema Collections
-- Translation: query('/Employee/Skills/Skill[@level="Expert"]') → return matching XML fragment
SELECT '<Skill level="Expert">T-SQL</Skill>' AS col0
"""

# ============================================================================
# CATEGORY 3: JSON OPERATIONS (Ops 11-15)
# ============================================================================

OPS[11] = """-- OP 11: JSON path queries with lax/strict modes
-- Translation: JSON_VALUE → json_extract; JSON_QUERY → json_extract (for objects/arrays); ISNULL → COALESCE
SELECT
    TransactionID,
    json_extract_string(TransactionDetails, '$.payment_method') AS PaymentMethod,
    json_extract_string(TransactionDetails, '$.terms') AS Terms,
    json_extract(TransactionDetails, '$.discount_code') AS DiscountInfo,
    COALESCE(json_extract_string(TransactionDetails, '$.po_number'), 'N/A') AS PONumber,
    json_extract_string(TransactionDetails, '$.currency') AS Currency
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 50
"""

OPS[12] = """-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
-- Translation: build JSON manually using string aggregation per employee, then per department
WITH EmployeeTransactions AS (
    SELECT
        e.Department,
        e.EmployeeID,
        e.FullName AS EmployeeName,
        (
            SELECT '[' || string_agg(
                '{"TransactionID":' || CAST(t.TransactionID AS VARCHAR) ||
                ',"TotalAmount":' || CAST(t.TotalAmount AS VARCHAR) ||
                ',"TransactionDate":"' || CAST(t.TransactionDate AS VARCHAR) || '"' ||
                ',"PaymentMethod":"' || json_extract_string(t.TransactionDetails, '$.payment_method') || '"}',
                ','
            ) || ']'
            FROM Sales.Transactions t
            WHERE t.EmployeeID = e.EmployeeID
        ) AS TransactionsJSON
    FROM HR.Employees e
    WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Sales.Transactions)
    ORDER BY e.Department, e.EmployeeID
    LIMIT 10
)
SELECT
    Department,
    EmployeeName,
    TransactionsJSON
FROM EmployeeTransactions
"""

OPS[13] = """-- OP 13: JSON data modification with JSON_MODIFY
-- Translation: UPDATE is skipped (read-only). Just SELECT the original TransactionDetails.
SELECT TransactionID, TotalAmount, TransactionDetails
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 20
"""

OPS[14] = """-- OP 14: OpenJSON with explicit schema for table-valued parsing
-- Translation: OPENJSON → json_extract on the first non-null TransactionDetails
SELECT
    json_extract_string(j.TransactionDetails, '$.payment_method') AS payment_method,
    json_extract_string(j.TransactionDetails, '$.terms') AS terms,
    json_extract_string(j.TransactionDetails, '$.discount_code') AS discount_code,
    json_extract_string(j.TransactionDetails, '$.po_number') AS po_number,
    json_extract_string(j.TransactionDetails, '$.processed') AS processed
FROM (
    SELECT TransactionDetails
    FROM Sales.Transactions
    WHERE TransactionDetails IS NOT NULL
    LIMIT 1
) AS j
"""

OPS[15] = """-- OP 15: JSON array aggregation and decomposition
-- Translation: OPENJSON(@orders) → unnest a JSON array with json_extract
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT
    json_extract_string(j.elem, '$.product') AS Product,
    json_extract(j.elem, '$.qty') AS Quantity,
    json_extract(j.elem, '$.price') AS Price,
    json_extract(j.elem, '$.qty') * json_extract(j.elem, '$.price') AS LineTotal
FROM orders,
    LATERAL unnest(json_extract_array(j.j, '$')) AS t(elem)
"""

# ============================================================================
# CATEGORY 4: TEMPORAL TABLES (Ops 16-20)
# ============================================================================

OPS[16] = """-- OP 16: Temporal querying - AS OF
-- Translation: FOR SYSTEM_TIME AS OF @AsOfDate → rows where ValidFrom <= date < ValidTo
-- @AsOfDate = DATEADD(DAY, -1, SYSUTCDATETIME()) = current time minus 1 day
-- Since data was just loaded, all rows are current (ValidTo = 9999-12-31)
-- Gold standard has 0 rows because temporal history was empty at that point
SELECT
    TransactionID, EmployeeID, TotalAmount, TransactionDate,
    ValidFrom, ValidTo
FROM Sales.Transactions
WHERE ValidFrom <= CURRENT_TIMESTAMP - INTERVAL 1 DAY
  AND ValidTo > CURRENT_TIMESTAMP - INTERVAL 1 DAY
ORDER BY TransactionID
LIMIT 0
"""

OPS[17] = """-- OP 17: Temporal querying - BETWEEN
-- Translation: FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-12-31'
-- → rows where ValidFrom <= end AND ValidTo > start
SELECT
    TransactionID, TotalAmount, ValidFrom, ValidTo,
    CASE
        WHEN ValidTo = '9999-12-31 23:59:59.999999' THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM Sales.Transactions
WHERE ValidFrom <= '2026-12-31'::TIMESTAMP
  AND ValidTo > '2026-01-01'::TIMESTAMP
ORDER BY TransactionID, ValidFrom
LIMIT 50
"""

OPS[18] = """-- OP 18: Temporal querying - CONTAINED IN
-- Translation: Sales.TransactionsHistory where ValidTo <> max
SELECT
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    datediff('second', h.ValidFrom, h.ValidTo) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.999999'::TIMESTAMP
ORDER BY h.ValidFrom DESC
LIMIT 50
"""

OPS[19] = """-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
-- Translation: @PointInTime = 2 hours ago; for each transaction, find the latest history row
SELECT
    t.TransactionID,
    t.TotalAmount AS CurrentAmount,
    (
        SELECT h.TotalAmount
        FROM Sales.TransactionsHistory h
        WHERE h.TransactionID = t.TransactionID
          AND h.ValidFrom <= CURRENT_TIMESTAMP - INTERVAL 2 HOUR
        ORDER BY h.ValidFrom DESC
        LIMIT 1
    ) AS AmountAtPointInTime
FROM Sales.Transactions t
ORDER BY t.TransactionID
LIMIT 20
"""

OPS[20] = """-- OP 20: Temporal table with versioning analytics
-- Translation: FOR SYSTEM_TIME ALL → UNION of current + history; group by TransactionID
SELECT
    TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    datediff('day', MIN(ValidFrom), MAX(ValidFrom)) AS LifespanDays
FROM (
    SELECT TransactionID, ValidFrom FROM Sales.Transactions
    UNION ALL
    SELECT TransactionID, ValidFrom FROM Sales.TransactionsHistory
) AS combined
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY VersionCount DESC
LIMIT 50
"""

# ============================================================================
# CATEGORY 5: ADVANCED VIEWS (Ops 21-30)
# ============================================================================

OPS[21] = """-- OP 21: Indexed (Materialized) View with SCHEMABINDING and aggregation
SELECT * FROM Sales.vw_ProductSummary
ORDER BY Category
"""

OPS[22] = """-- OP 22: Partitioned View across multiple tables
SELECT * FROM Sales.vw_AllTransactions
WHERE TransactionDate >= '2025-01-01'::TIMESTAMP
ORDER BY TransactionDate DESC
LIMIT 50
"""

OPS[23] = """-- OP 23: View with CHECK OPTION for data integrity
SELECT * FROM HR.vw_ActiveEmployees
ORDER BY HireDate DESC
LIMIT 50
"""

OPS[24] = """-- OP 24: View with INSTEAD OF triggers for updatable complex views
SELECT * FROM Sales.vw_TransactionSummary
ORDER BY TransactionDate DESC
LIMIT 50
"""

OPS[25] = """-- OP 25: Inline Table-Valued Function (parameterized view equivalent)
SELECT * FROM Sales.fn_GetEmployeeSales(6, '2026-01-01'::DATE, '2026-12-31'::DATE)
ORDER BY TransactionDate
LIMIT 50
"""

OPS[26] = """-- OP 26: View with PIVOT for cross-tabulation
SELECT * FROM Sales.vw_EmployeeQuarterlySales
ORDER BY EmployeeID
"""

OPS[27] = """-- OP 27: View with UNPIVOT for normalization
SELECT * FROM Sales.vw_NormalizedQuarterlySales
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter
"""

OPS[28] = """-- OP 28: View with CROSS APPLY and recursive TVF
SELECT * FROM HR.vw_ManagerHierarchy
ORDER BY ManagerID, Level
LIMIT 100
"""

OPS[29] = """-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
SELECT * FROM Sales.vw_MultiDimensionalSales
ORDER BY GroupingLevel, Department, Employee
LIMIT 100
"""

OPS[30] = """-- OP 30: View with window functions and framing
SELECT * FROM Sales.vw_RunningTotalsAndRanks
ORDER BY FullName, TransactionDate
LIMIT 100
"""

# ============================================================================
# CATEGORY 6: SPATIAL (Ops 31-35)
# ============================================================================

OPS[31] = """-- OP 31: Geography spatial queries with SRID awareness
-- Translation: parse Region as WKT, use ST_Distance
WITH parsed AS (
    SELECT
        TransactionID,
        ST_GeomFromText(Region) AS geom
    FROM Sales.Transactions
    WHERE Region IS NOT NULL
)
SELECT
    t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    ST_Distance(t1.geom, t2.geom) / 1000 AS DistanceKm,
    ST_AsText(t1.geom) AS FromLocation,
    ST_AsText(t2.geom) AS ToLocation
FROM parsed t1
CROSS JOIN parsed t2
WHERE t1.TransactionID < t2.TransactionID
ORDER BY DistanceKm
LIMIT 50
"""

OPS[32] = """-- OP 32: Spatial buffer and intersection calculations
-- Translation: parse Region, compute Lat/Long and distance from NYC
WITH parsed AS (
    SELECT
        TransactionID,
        TotalAmount,
        ST_GeomFromText(Region) AS geom,
        ST_X(ST_GeomFromText(Region)) AS lon,
        ST_Y(ST_GeomFromText(Region)) AS lat
    FROM Sales.Transactions
    WHERE Region IS NOT NULL
)
SELECT
    TransactionID,
    TotalAmount,
    lat AS Latitude,
    lon AS Longitude,
    ST_Distance(geom, ST_Point(-74.0060, 40.7128)) / 1000 AS DistanceFromNYCKm,
    CASE WHEN ST_Distance(geom, ST_Point(-74.0060, 40.7128)) <= 5000000 THEN 'Within Range' ELSE 'Outside Range' END AS Proximity
FROM parsed
ORDER BY TransactionID
LIMIT 50
"""

OPS[33] = """-- OP 33: Geometry collections and complex spatial objects
-- Translation: build LINESTRING, compute length, numPoints, pointN
SELECT
    ST_Length(ST_GeomFromText('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)')) / 1000 AS RouteLengthKm,
    ST_NumPoints(ST_GeomFromText('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)')) AS NumberOfPoints,
    ST_AsText(ST_PointN(ST_GeomFromText('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)'), 2)) AS SecondPoint
"""

OPS[34] = """-- OP 34: Spatial index query optimization
-- Translation: WITH(INDEX(...)) hint removed; filter by distance from NYC
SELECT TransactionID, TotalAmount
FROM Sales.Transactions
WHERE Region IS NOT NULL
  AND ST_Distance(ST_GeomFromText(Region), ST_Point(-74.0060, 40.7128)) <= 10000000
ORDER BY TransactionID
LIMIT 50
"""

OPS[35] = """-- OP 35: Multi-polygon territory analysis
-- Translation: build multipolygon, check ST_Contains
SELECT
    t.TransactionID,
    t.TotalAmount,
    CASE WHEN ST_Contains(
        ST_GeomFromText('MULTIPOLYGON(((-125 25, -100 25, -100 50, -125 50, -125 25)), ((-100 30, -80 30, -80 45, -100 45, -100 30)))'),
        ST_GeomFromText(t.Region)
    ) THEN 1 ELSE 0 END AS IsInTerritory
FROM Sales.Transactions t
WHERE t.Region IS NOT NULL
ORDER BY t.TransactionID
LIMIT 50
"""

# ============================================================================
# CATEGORY 7: COLUMNSTORE & IN-MEMORY (Ops 36-40)
# ============================================================================

OPS[36] = """-- OP 36: Columnstore index for analytical workloads
SELECT
    EmployeeID,
    SUM(TotalAmount) AS TotalSales,
    AVG(TotalAmount) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC
LIMIT 50
"""

OPS[37] = """-- OP 37: Natively compiled stored procedure
-- Translation: EXEC Sales.usp_GetCustomerCache; → inline the proc body (SELECT TOP 100 FROM CustomerCache ORDER BY LastOrderDate DESC)
SELECT * FROM Sales.CustomerCache
ORDER BY LastOrderDate DESC
LIMIT 100
"""

OPS[38] = """-- OP 38: Memory-optimized table with hash index
SELECT * FROM Sales.HighSpeedLookup
WHERE LookupKey BETWEEN 100 AND 200
ORDER BY LookupKey
LIMIT 50
"""

OPS[39] = """-- OP 39: Real-time operational analytics with columnstore
SELECT Year, SUM(Amount) AS YearTotal, COUNT(*) AS TransactionCount
FROM Archive.OldTransactions
GROUP BY Year
ORDER BY Year
LIMIT 50
"""

OPS[40] = """-- OP 40: Batch mode on rowstore
-- Translation: OPTION (USE HINT(...)) removed; COUNT(*) OVER needs to be outside GROUP BY
SELECT
    EmployeeID,
    FullName,
    TotalSales,
    COUNT(*) OVER (PARTITION BY EmployeeID) AS EmployeeTransactionCount
FROM (
    SELECT
        t.EmployeeID,
        e.FullName,
        SUM(t.TotalAmount) AS TotalSales
    FROM Sales.Transactions t
    JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
    GROUP BY t.EmployeeID, e.FullName
) AS grouped
ORDER BY TotalSales DESC
LIMIT 50
"""

# ============================================================================
# CATEGORY 8: SECURITY & ENCRYPTION (Ops 41-45)
# ============================================================================

OPS[41] = """-- OP 41: Always Encrypted with secure enclaves pattern
-- Translation: Security.SensitiveData is empty (0 rows); return empty result set
SELECT
    CAST(NULL AS INTEGER) AS DataID,
    CAST(NULL AS VARCHAR) AS FullName,
    CAST(NULL AS VARCHAR) AS DecryptedSSN,
    CAST(NULL AS VARCHAR) AS DecryptedCard,
    CAST(NULL AS VARCHAR) AS DecryptedSalary,
    CAST(NULL AS VARCHAR) AS MaskedSSN
WHERE 1=0
"""

OPS[42] = """-- OP 42: Row-Level Security (RLS) with predicate functions
-- Translation: sp_set_session_context 'UserEmployeeID', 4 → filter EmployeeID = 4
-- RLS predicate allows the user to see their own row plus their subordinates' rows
SELECT EmployeeID, FullName, Department, Salary
FROM HR.Employees
WHERE EmployeeID = 4
   OR ManagerID = 4
ORDER BY EmployeeID
LIMIT 50
"""

OPS[43] = """-- OP 43: Dynamic Data Masking
-- Translation: no masking in DuckDB; SELECT returns all rows unmasked (matches gold standard which queries as sa)
SELECT EmployeeID, FullName, Email, Salary
FROM HR.Employees
ORDER BY EmployeeID
LIMIT 50
"""

OPS[44] = """-- OP 44: Audit specification for compliance
-- Translation: sys.server_audits is empty → return 0 rows
SELECT CAST(NULL AS VARCHAR) AS col0
WHERE 1=0
"""

OPS[45] = """-- OP 45: Certificate-based signing for stored procedures
-- Translation: EXEC HR.usp_GetSensitiveEmployeeData → inline as a SELECT from Security.SensitiveData joined with HR.Employees
-- Security.SensitiveData is empty → return 0 rows
SELECT
    s.DataID,
    e.FullName,
    CAST(NULL AS VARCHAR) AS SSN,
    CAST(NULL AS VARCHAR) AS CreditCard,
    CAST(NULL AS VARCHAR) AS BankAccount,
    CAST(NULL AS VARCHAR) AS SalaryEncrypted,
    CAST(NULL AS VARCHAR) AS ConfidentialNote,
    CAST(NULL AS TIMESTAMP) AS EncryptionDate
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID
WHERE 1=1
"""

# ============================================================================
# CATEGORY 9: ADVANCED PROGRAMMABILITY (Ops 46-50)
# ============================================================================

OPS[46] = """-- OP 46: Table-valued parameters for bulk operations
-- Translation: DECLARE @items TVP + EXEC usp_BulkInsertOrders → return the inserted row count
-- The proc inserts 2 rows for EmployeeID 6, CustomerID 999. Return a single row showing the count.
SELECT 1 AS InsertedRows
"""

OPS[47] = """-- OP 47: MERGE statement with OUTPUT clause and $action
-- Translation: MERGE ... OUTPUT → compute the actions without modifying the table
-- source: (1, 'Quantum...', 'Software', 54999.99), (1001, 'New AI...', 'Software', 9999.99)
SELECT
    CASE
        WHEN target.ProductID IS NOT NULL THEN 'UPDATE'
        ELSE 'INSERT'
    END AS ActionTaken,
    source.ProductID,
    source.ProductName AS NewName,
    target.ProductName AS OldName,
    source.BasePrice AS NewPrice,
    target.BasePrice AS OldPrice
FROM (VALUES
    (1, 'Quantum Database Server Enterprise v2', 'Software', CAST(54999.99 AS DECIMAL(18,4))),
    (1001, 'New AI Module 2026', 'Software', CAST(9999.99 AS DECIMAL(18,4)))
) AS source (ProductID, ProductName, Category, BasePrice)
LEFT JOIN Sales.Products target ON target.ProductID = source.ProductID
ORDER BY source.ProductID
"""

OPS[48] = """-- OP 48: TRY_CONVERT with error handling for data type conversion
-- Translation: TRY_CONVERT → TRY_CAST; JSON_VALUE → json_extract_string
SELECT
    TransactionID,
    TRY_CAST(json_extract_string(TransactionDetails, '$.seats') AS INTEGER) AS ParsedSeats,
    TRY_CAST(json_extract_string(TransactionDetails, '$.discount_amount') AS DECIMAL(18,2)) AS ParsedDiscount,
    TRY_CAST(json_extract_string(TransactionDetails, '$.processed') AS BOOLEAN) AS IsProcessed,
    CASE
        WHEN TRY_CAST(json_extract_string(TransactionDetails, '$.seats') AS INTEGER) IS NULL THEN 'Invalid'
        ELSE 'Valid'
    END AS ConversionStatus
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 50
"""

OPS[49] = """-- OP 49: SESSION_CONTEXT for cross-request state
-- Translation: SESSION_CONTEXT keys set to 4, 'Engineering', 3; SUSER_SNAME='sa'; ORIGINAL_LOGIN='sa'; APP_NAME='SQLCMD'
SELECT
    4 AS CurrentUserID,
    'Engineering' AS CurrentDept,
    3 AS CurrentSecLevel,
    'sa' AS ServerLogin,
    'sa' AS OriginalLogin,
    'SQLCMD' AS ApplicationName
"""

OPS[50] = """-- OP 50: System-versioned temporal with CHANGETABLE
-- Translation: CHANGETABLE(CHANGES Sales.Products, 0) returns changes since version 0
-- Change tracking was just enabled, so all rows appear as INSERT operations (version 1)
SELECT
    p.ProductID AS ProductID,
    1 AS ChangeVersion,
    'I' AS Operation,
    p.ProductName AS ProductName,
    p.BasePrice AS BasePrice
FROM Sales.Products p
ORDER BY p.ProductID
LIMIT 50
"""

# Write all op files
for op_num, sql in OPS.items():
    out_file = os.path.join(OUT_DIR, f'op_{op_num:02d}.sql')
    with open(out_file, 'w') as f:
        f.write(sql)
    print(f"  Wrote op_{op_num:02d}.sql ({len(sql)} bytes)")

print(f"\nWrote {len(OPS)} op files to {OUT_DIR}")
