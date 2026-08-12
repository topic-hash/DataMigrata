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

