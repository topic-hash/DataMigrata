-- OP 4: Recursive CTE with path enumeration and string aggregation
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
