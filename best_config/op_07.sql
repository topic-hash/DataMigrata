-- OP 7: XML shredding with nodes() method and cross apply
SELECT
    e.EmployeeID,
    e.FullName,
    regexp_extract(m.skill, 'level="([^"]+)"', 1) AS SkillLevel,
    regexp_extract(m.skill, '>([^<]+)<', 1) AS SkillName
FROM HR.Employees e,
    LATERAL (
        SELECT unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS skill
    ) AS m
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel
LIMIT 50
