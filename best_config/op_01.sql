-- OP 1: Recursive CTE with HIERARCHYID path building and cycle detection
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
