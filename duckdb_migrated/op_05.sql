-- OP 5: Closure table pattern using recursive CTE for transitive relationships
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
