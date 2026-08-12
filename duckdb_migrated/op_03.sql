-- OP 3: HIERARCHYID data type for optimized tree operations
WITH OrgChartParsed AS (
    SELECT
        o.OrgNode AS Path,
        o.OrgLevel,
        e.FullName,
        e.JobTitle,
        o.PositionTitle,
        -- GetAncestor(1).ToString(): parent path = remove last segment
        CASE
            WHEN o.OrgNode = '/' THEN '/'
            ELSE regexp_replace(regexp_replace(o.OrgNode, '/[^/]+/$', '/'), '^/$', '/')
        END AS ParentPath,
        1 AS IsUnderRoot,
        -- Parse path segments for sorting: /1/ < /2/ < /10/
        CAST(string_to_array(trim(o.OrgNode, '/'), '/') AS BIGINT[]) AS PathSegs
    FROM HR.OrgChart o
    JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
)
SELECT Path, OrgLevel, FullName, JobTitle, PositionTitle, ParentPath, IsUnderRoot
FROM OrgChartParsed
ORDER BY PathSegs
LIMIT 100
