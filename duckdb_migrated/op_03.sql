-- OP 3: HIERARCHYID data type for optimized tree operations
-- Translated from T-SQL to DuckDB dialect

SELECT     o.OrgNode AS Path,
    o.OrgLevel,
    e.FullName,
    e.JobTitle,
    o.PositionTitle,
    o.OrgNode AS ParentPath,
    o.OrgNode= '/' AS IsUnderRoot
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrgNode
LIMIT 100
