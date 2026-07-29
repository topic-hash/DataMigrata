-- OP 7: XML shredding with nodes() method and cross apply
-- Translated from T-SQL to DuckDB dialect

SELECT     e.EmployeeID,
    e.FullName,
    skill.value('NULL', 'VARCHAR(20)') AS SkillLevel,
    skill.value('.', 'VARCHAR(100)') AS SkillName
FROM HR.Employees e
JOIN LATERAL e.EmployeeData.nodes('/Employee/Skills/Skill') AS Skills(skill)
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel
LIMIT 50
