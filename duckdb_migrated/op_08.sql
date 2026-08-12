-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
SELECT
    e.EmployeeID,
    e.FullName,
    '<Skills>' || string_agg(
        '<Skill name="' || regexp_extract(m.skill, '>([^<]+)<', 1) ||
        '" level="' || regexp_extract(m.skill, 'level="([^"]+)"', 1) ||
        '"/>', ''
    ) || '</Skills>' AS SkillsXML
FROM HR.Employees e,
    LATERAL (
        SELECT unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS skill
    ) AS m
WHERE e.EmployeeData IS NOT NULL
GROUP BY e.EmployeeID, e.FullName
ORDER BY e.EmployeeID
LIMIT 20
