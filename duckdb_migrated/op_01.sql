-- OP 1: Recursive CTE with HIERARCHYID path building and cycle detection
-- Translated from T-SQL to DuckDB dialect

WITH RECURSIVE EmployeeHierarchy AS (
    SELECT 
        EmployeeID, ManagerID, FullName, Department, Salary, JobTitle,
        CAST(FullName AS TEXT) AS HierarchyPath,
        0 AS Level,
        CAST(EmployeeID AS TEXT) AS PathString,
        CAST(Salary AS DECIMAL(18,2)) AS CumulativeSalary
    FROM HR.Employees
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT 
        e.EmployeeID, e.ManagerID, e.FullName, e.Department, e.Salary, e.JobTitle,
        CAST(h.HierarchyPath + ' > ' + e.FullName AS TEXT),
        h.Level + 1,
        CAST(h.PathString + '.' + CAST(e.EmployeeID AS VARCHAR) AS TEXT),
        CAST(h.CumulativeSalary + e.Salary AS DECIMAL(18,2))
    FROM HR.Employees e
    INNER JOIN EmployeeHierarchy h ON e.ManagerID = h.EmployeeID
    WHERE h.Level < 10
)
SELECT     EmployeeID, FullName, Department, JobTitle, Salary, Level,
    HierarchyPath,
    CumulativeSalary,
    repeat('  ', Level) + FullName AS IndentedDisplay
FROM EmployeeHierarchy
ORDER BY PathString
LIMIT 100
