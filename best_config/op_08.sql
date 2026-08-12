-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
-- Gold: <Skills> wrapper with self-closing <Skill/> tags, in original XML order
-- Use list_extract with positional index to preserve order (unnest reverses)
WITH employee_skills AS (
    SELECT
        e.EmployeeID,
        e.FullName,
        regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>') AS skills_list
    FROM HR.Employees e
    WHERE e.EmployeeData IS NOT NULL
)
SELECT
    e.EmployeeID,
    e.FullName,
    '<Skills>' || (
        SELECT string_agg(
            '<Skill name="' || regexp_extract(list_extract(e.skills_list, i), '>([^<]+)<', 1) ||
            '" level="' || regexp_extract(list_extract(e.skills_list, i), 'level="([^"]+)"', 1) ||
            '"/>', ''
        )
        FROM generate_series(1, len(e.skills_list)) AS t(i)
    ) || '</Skills>' AS SkillsXML
FROM employee_skills e
ORDER BY e.EmployeeID
LIMIT 20
