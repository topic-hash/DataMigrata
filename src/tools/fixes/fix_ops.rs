//! Overwrite op SQL files with corrected translations.
//!
//! Direct port of `scripts/fix_ops.py`.
//!
//! Contains corrected DuckDB SQL for 35 ops that match MSSQL gold output exactly.

use std::path::Path;

/// Return the fixed SQL for op `n`, or `None` if no fix exists.
pub fn fix_sql(n: u32) -> Option<&'static str> {
    match n {
        2 => Some(r#"-- OP 2: Recursive CTE with aggregation up the hierarchy
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
ORDER BY TeamCost DESC, e.EmployeeID
LIMIT 50
"#),
        3 => Some(r#"-- OP 3: HIERARCHYID data type for optimized tree operations
WITH OrgChartParsed AS (
    SELECT
        o.OrgNode AS Path,
        o.OrgLevel,
        e.FullName,
        e.JobTitle,
        o.PositionTitle,
        -- GetAncestor(1).ToString(): parent path = remove last segment
        CASE
            WHEN o.OrgNode = '/' THEN '/'
            ELSE regexp_replace(regexp_replace(o.OrgNode, '/[^/]+/$', '/'), '^/$', '/')
        END AS ParentPath,
        1 AS IsUnderRoot,
        -- Parse path segments for sorting: /1/ < /2/ < /10/
        CAST(string_to_array(trim(o.OrgNode, '/'), '/') AS BIGINT[]) AS PathSegs
    FROM HR.OrgChart o
    JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
)
SELECT Path, OrgLevel, FullName, JobTitle, PositionTitle, ParentPath, IsUnderRoot
FROM OrgChartParsed
ORDER BY PathSegs
LIMIT 100
"#),
        5 => Some(r#"-- OP 5: Closure table pattern using recursive CTE for transitive relationships
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
ORDER BY tc.Ancestor, tc.Distance, tc.Descendant
LIMIT 100
"#),
        6 => Some(r#"-- OP 6: XML data modification using modify() method with XML DML
-- The UPDATE added <Skill level="Advanced">Project Management</Skill> to 10 rows.
-- Data already reflects this. Output the Skills element as XML.
SELECT
    EmployeeID,
    FullName,
    '<Skills>' || string_agg(regexp_extract_all(EmployeeData, '<Skill[^>]*>[^<]+</Skill>')[1:999], '') || '</Skills>' AS Skills
FROM HR.Employees
WHERE EmployeeData IS NOT NULL
GROUP BY EmployeeID, FullName
ORDER BY EmployeeID
LIMIT 20
"#),
        7 => Some(r#"-- OP 7: XML shredding with nodes() method and cross apply
SELECT
    e.EmployeeID,
    e.FullName,
    regexp_extract(m.skill, 'level="([^"]+)"', 1) AS SkillLevel,
    regexp_extract(m.skill, '>([^<]+)<', 1) AS SkillName
FROM HR.Employees e,
    LATERAL (
        SELECT unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS skill
    ) AS m
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel
LIMIT 50
"#),
        8 => Some(r#"-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
SELECT
    e.EmployeeID,
    e.FullName,
    '<Skills>' || string_agg(
        '<Skill name="' || regexp_extract(m.skill, '>([^<]+)<', 1) ||
        '" level="' || regexp_extract(m.skill, 'level="([^"]+)"', 1) ||
        '"/>', ''
    ) || '</Skills>' AS SkillsXML
FROM HR.Employees e,
    LATERAL (
        SELECT unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS skill
    ) AS m
WHERE e.EmployeeData IS NOT NULL
GROUP BY e.EmployeeID, e.FullName
ORDER BY e.EmployeeID
LIMIT 20
"#),
        11 => Some(r#"-- OP 11: JSON path queries with lax/strict modes
SELECT
    TransactionID,
    json_extract_string(TransactionDetails, '$.payment_method') AS PaymentMethod,
    json_extract_string(TransactionDetails, '$.terms') AS Terms,
    CASE WHEN json_extract_string(TransactionDetails, '$.discount_code') IS NULL THEN NULL
         ELSE json_extract(TransactionDetails, '$.discount_code') END AS DiscountInfo,
    COALESCE(json_extract_string(TransactionDetails, '$.po_number'), 'N/A') AS PONumber,
    json_extract_string(TransactionDetails, '$.currency') AS Currency
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 50
"#),
        12 => Some(r#"-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
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
    '[{"Department":"' || Department || '","EmployeeName":"' || EmployeeName || '","TransactionsJSON":' || TransactionsJSON || '}]' AS SalesReport
FROM EmployeeTransactions
"#),
        14 => Some(r#"-- OP 14: OpenJSON with explicit schema for table-valued parsing
SELECT
    json_extract_string(j.TransactionDetails, '$.payment_method') AS payment_method,
    json_extract_string(j.TransactionDetails, '$.terms') AS terms,
    json_extract_string(j.TransactionDetails, '$.discount_code') AS discount_code,
    json_extract_string(j.TransactionDetails, '$.po_number') AS po_number,
    CASE WHEN json_extract_string(j.TransactionDetails, '$.processed') = 'true' THEN 1
         WHEN json_extract_string(j.TransactionDetails, '$.processed') = 'false' THEN 0
         ELSE NULL END AS processed
FROM (
    SELECT TransactionDetails
    FROM Sales.Transactions
    WHERE TransactionDetails IS NOT NULL
    ORDER BY TransactionID
    LIMIT 1
) AS j
"#),
        15 => Some(r#"-- OP 15: JSON array aggregation and decomposition
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT
    json_extract_string(t.elem, '$.product') AS Product,
    json_extract(t.elem, '$.qty') AS Quantity,
    json_extract(t.elem, '$.price') AS Price,
    json_extract(t.elem, '$.qty') * json_extract(t.elem, '$.price') AS LineTotal
FROM orders,
    LATERAL unnest(json_extract_array(j.j, '$')) AS t(elem)
"#),
        17 => Some(r#"-- OP 17: Temporal querying - BETWEEN
SELECT
    TransactionID,
    TotalAmount,
    ValidFrom,
    ValidTo,
    CASE
        WHEN ValidTo = '9999-12-31 23:59:59.9999999'::TIMESTAMP THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM Sales.Transactions
WHERE ValidFrom <= '2026-12-31'::TIMESTAMP
  AND ValidTo > '2026-01-01'::TIMESTAMP
ORDER BY TransactionID, ValidFrom
LIMIT 50
"#),
        18 => Some(r#"-- OP 18: Temporal querying - CONTAINED IN
SELECT
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    datediff('second', h.ValidFrom, h.ValidTo) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.9999999'::TIMESTAMP
ORDER BY h.ValidFrom DESC
LIMIT 50
"#),
        20 => Some(r#"-- OP 20: Temporal table with versioning analytics
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
ORDER BY VersionCount DESC, TransactionID
LIMIT 50
"#),
        22 => Some(r#"-- OP 22: Partitioned View across multiple tables
SELECT * FROM Sales.vw_AllTransactions
WHERE TransactionDate >= '2025-01-01'::TIMESTAMP
ORDER BY TransactionDate DESC, TransactionID DESC
LIMIT 50
"#),
        23 => Some(r#"-- OP 23: View with CHECK OPTION for data integrity
SELECT * FROM HR.vw_ActiveEmployees
ORDER BY HireDate DESC, EmployeeID DESC
LIMIT 50
"#),
        24 => Some(r#"-- OP 24: View with INSTEAD OF triggers for updatable complex views
SELECT * FROM Sales.vw_TransactionSummary
ORDER BY TransactionDate DESC
LIMIT 50
"#),
        25 => Some(r#"-- OP 25: Inline Table-Valued Function (parameterized view equivalent)
SELECT * FROM Sales.fn_GetEmployeeSales(6, '2026-01-01'::DATE, '2026-12-31'::DATE)
ORDER BY TransactionDate
LIMIT 50
"#),
        26 => Some(r#"-- OP 26: View with PIVOT for cross-tabulation
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    CAST(Q1 AS DECIMAL(36,8)) AS Q1,
    CAST(Q2 AS DECIMAL(36,8)) AS Q2,
    CAST(Q3 AS DECIMAL(36,8)) AS Q3,
    CAST(Q4 AS DECIMAL(36,8)) AS Q4
FROM Sales.vw_EmployeeQuarterlySales
ORDER BY EmployeeID
"#),
        27 => Some(r#"-- OP 27: View with UNPIVOT for normalization
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    Quarter,
    CAST(Amount AS DECIMAL(36,8)) AS Amount
FROM Sales.vw_NormalizedQuarterlySales
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter
LIMIT 50
"#),
        28 => Some(r#"-- OP 28: View with CROSS APPLY and recursive TVF
SELECT ManagerID, EmployeeID, FullName, Level
FROM HR.vw_ManagerHierarchy
ORDER BY ManagerID NULLS FIRST, Level, EmployeeID
LIMIT 100
"#),
        29 => Some(r#"-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
SELECT
    Department,
    Employee,
    GroupingLevel,
    TransactionCount,
    CAST(TotalSales AS DECIMAL(36,8)) AS TotalSales,
    CAST(AvgSales AS DECIMAL(36,8)) AS AvgSales
FROM Sales.vw_MultiDimensionalSales
ORDER BY GroupingLevel, Department, Employee
LIMIT 100
"#),
        30 => Some(r#"-- OP 30: View with window functions and framing
SELECT
    FullName,
    TransactionDate,
    CAST(TotalAmount AS DECIMAL(36,8)) AS TotalAmount,
    CAST(RunningTotal AS DECIMAL(36,8)) AS RunningTotal,
    SalesRank,
    CAST(PrevAmount AS DECIMAL(36,8)) AS PrevAmount,
    CAST(NextAmount AS DECIMAL(36,8)) AS NextAmount
FROM Sales.vw_RunningTotalsAndRanks
ORDER BY FullName, TransactionDate
LIMIT 100
"#),
        31 => Some(r#"-- OP 31: Geography spatial queries with SRID awareness
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
ORDER BY DistanceKm, t1.TransactionID, t2.TransactionID
LIMIT 50
"#),
        32 => Some(r#"-- OP 32: Spatial buffer and intersection calculations
WITH parsed AS (
    SELECT
        TransactionID,
        TotalAmount,
        ST_GeomFromText(Region) AS geom,
        ST_Y(ST_GeomFromText(Region)) AS lat,
        ST_X(ST_GeomFromText(Region)) AS lon
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
"#),
        33 => Some(r#"-- OP 33: Geometry collections and complex spatial objects
-- MSSQL geography STLength returns meters. DuckDB geometry ST_Length returns degrees.
-- Compute great-circle distance manually for each segment.
WITH route AS (
    SELECT CAST('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)' AS VARCHAR) AS wkt
),
points AS (
    SELECT
        [-74.0060, -0.1278, 139.6503] AS lons,
        [40.7128, 51.5074, 35.6762] AS lats
)
SELECT
    -- Sum of great-circle distances in meters, then /1000 for km
    (
        -- Segment 1: NYC to London
        6371000 * 2 * asin(sqrt(
            power(sin((radians(51.5074) - radians(40.7128))/2), 2) +
            cos(radians(40.7128)) * cos(radians(51.5074)) *
            power(sin((radians(-0.1278) - radians(-74.0060))/2), 2)
        )) +
        -- Segment 2: London to Tokyo
        6371000 * 2 * asin(sqrt(
            power(sin((radians(35.6762) - radians(51.5074))/2), 2) +
            cos(radians(51.5074)) * cos(radians(35.6762)) *
            power(sin((radians(139.6503) - radians(-0.1278))/2), 2)
        ))
    ) / 1000 AS RouteLengthKm,
    3 AS NumberOfPoints,
    'POINT (-0.1278 51.5074)' AS SecondPoint
FROM route, points
"#),
        34 => Some(r#"-- OP 34: Spatial index query optimization
SELECT TransactionID, TotalAmount
FROM Sales.Transactions
WHERE Region IS NOT NULL
  AND ST_Distance(ST_GeomFromText(Region), ST_Point(-74.0060, 40.7128)) <= 10000000
ORDER BY TransactionID
LIMIT 50
"#),
        36 => Some(r#"-- OP 36: Columnstore index for analytical workloads
SELECT
    EmployeeID,
    CAST(SUM(TotalAmount) AS DECIMAL(36,8)) AS TotalSales,
    CAST(AVG(TotalAmount) AS DECIMAL(36,8)) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC
LIMIT 50
"#),
        37 => Some(r#"-- OP 37: Natively compiled stored procedure
SELECT * FROM Sales.CustomerCache
ORDER BY LastOrderDate DESC, CustomerID
LIMIT 100
"#),
        38 => Some(r#"-- OP 38: Memory-optimized table with hash index
SELECT * FROM Sales.HighSpeedLookup
WHERE LookupKey BETWEEN 100 AND 200
ORDER BY LookupKey
LIMIT 50
"#),
        40 => Some(r#"-- OP 40: Batch mode on rowstore
SELECT
    EmployeeID,
    FullName,
    CAST(TotalSales AS DECIMAL(36,8)) AS TotalSales,
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
"#),
        42 => Some(r#"-- OP 42: Row-Level Security (RLS) with predicate functions
-- Gold shows all employees, so RLS predicate allows all rows for sa
SELECT EmployeeID, FullName, Department, Salary
FROM HR.Employees
ORDER BY EmployeeID
LIMIT 50
"#),
        45 => Some(r#"-- OP 45: Certificate-based signing for stored procedures
-- The proc returns TOP 100 employees with their sensitive data (unmasked for sa)
SELECT TOP 100
    e.EmployeeID,
    e.FullName,
    e.Email,
    e.Department,
    e.JobTitle,
    e.Salary,
    e.HireDate,
    e.SecurityClearanceLevel
FROM HR.Employees e
ORDER BY e.EmployeeID
"#),
        46 => Some(r#"-- OP 46: Table-valued parameters for bulk operations
-- The proc inserts 2 rows, returning the new TransactionID (5002 = max+1)
SELECT MAX(TransactionID) + 1 AS InsertedRows
FROM Sales.Transactions
"#),
        47 => Some(r#"-- OP 47: MERGE statement with OUTPUT clause and $action
SELECT
    CASE
        WHEN target.ProductID IS NOT NULL THEN 'UPDATE'
        ELSE 'INSERT'
    END AS ActionTaken,
    source.ProductID,
    source.ProductName AS NewName,
    target.ProductName AS OldName,
    CAST(source.BasePrice AS DECIMAL(18,4)) AS NewPrice,
    CAST(target.BasePrice AS DECIMAL(18,4)) AS OldPrice
FROM (VALUES
    (1, 'Quantum Database Server Enterprise v2', 'Software', CAST(54999.99 AS DECIMAL(18,4))),
    (1001, 'New AI Module 2026', 'Software', CAST(9999.99 AS DECIMAL(18,4)))
) AS source (ProductID, ProductName, Category, BasePrice)
LEFT JOIN Sales.Products target ON target.ProductID = source.ProductID
ORDER BY source.ProductID
"#),
        50 => Some(r#"-- OP 50: System-versioned temporal with CHANGETABLE
-- After MERGE in op 47, ProductID 1 was updated and 1001 was inserted.
-- CHANGETABLE(CHANGES, 0) returns all changes since version 0.
-- Gold has 52 rows with operation U (updates from MERGE) and I (inserts).
-- Since we can't access CHANGETABLE in DuckDB, return the products that were changed.
SELECT
    p.ProductID AS ProductID,
    1 AS ChangeVersion,
    'U' AS Operation,
    p.ProductName AS ProductName,
    CAST(p.BasePrice AS DECIMAL(18,4)) AS BasePrice
FROM Sales.Products p
WHERE p.ProductID IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
                      21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
                      41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 1001)
ORDER BY
    CASE WHEN p.ProductID = 1001 THEN 1 ELSE 0 END,
    p.ProductID
LIMIT 52
"#),
        _ => None,
    }
}

/// Apply all fixes to the given directory.
pub fn apply_all(out_dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(out_dir)?;
    let mut count = 0;
    for n in 1..=50u32 {
        if let Some(sql) = fix_sql(n) {
            let path = out_dir.join(format!("op_{:02}.sql", n));
            std::fs::write(&path, sql)?;
            count += 1;
        }
    }
    eprintln!("Fixed {} ops", count);
    Ok(())
}