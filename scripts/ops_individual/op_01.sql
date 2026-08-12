-- OP 1: Recursive CTE with HIERARCHYID path building and cycle detection
WITH EmployeeHierarchy AS (
    SELECT 
        EmployeeID, ManagerID, FullName, Department, Salary, JobTitle,
        CAST(FullName AS NVARCHAR(MAX)) AS HierarchyPath,
        0 AS Level,
        CAST(EmployeeID AS VARCHAR(MAX)) AS PathString,
        CAST(Salary AS DECIMAL(18,2)) AS CumulativeSalary
    FROM HR.Employees
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT 
        e.EmployeeID, e.ManagerID, e.FullName, e.Department, e.Salary, e.JobTitle,
        CAST(h.HierarchyPath + ' > ' + e.FullName AS NVARCHAR(MAX)),
        h.Level + 1,
        CAST(h.PathString + '.' + CAST(e.EmployeeID AS VARCHAR) AS VARCHAR(MAX)),
        CAST(h.CumulativeSalary + e.Salary AS DECIMAL(18,2))
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

