-- OP 2: Recursive CTE with aggregation up the hierarchy
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
