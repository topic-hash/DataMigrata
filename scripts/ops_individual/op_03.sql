-- OP 3: HIERARCHYID data type for optimized tree operations
SELECT TOP 100
    o.OrgNode.ToString() AS Path,
    o.OrgLevel,
    e.FullName,
    e.JobTitle,
    o.PositionTitle,
    o.OrgNode.GetAncestor(1).ToString() AS ParentPath,
    o.OrgNode.IsDescendantOf(HIERARCHYID::Parse('/')) AS IsUnderRoot
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrgNode;
GO

