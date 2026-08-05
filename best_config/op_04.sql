-- OP 4: Recursive CTE with path enumeration and string aggregation
-- Translated from T-SQL to DuckDB dialect

WITH RECURSIVE OrgPath AS (
    SELECT EmployeeID, ManagerID, FullName, 
           CAST(FullName AS TEXT) AS Path,
           CAST(CAST(EmployeeID AS VARCHAR(10)) AS TEXT) AS IdPath
    FROM HR.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FullName,
           p.Path + ' -> ' + e.FullName,
           p.IdPath + ',' + CAST(e.EmployeeID AS VARCHAR(10))
    FROM HR.Employees e
    JOIN OrgPath p ON e.ManagerID = p.EmployeeID
)
SELECT EmployeeID, FullName, Path, IdPath,
       length(IdPath) - length(REPLACE(IdPath, ',', '')) + 1 AS Depth
FROM OrgPath
ORDER BY IdPath
LIMIT 100
