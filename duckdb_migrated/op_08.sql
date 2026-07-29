-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
-- Translated from T-SQL to DuckDB dialect

SELECT     EmployeeID,
    FullName,
    (SELECT 
        Skill.value('.', 'VARCHAR(100)') AS 'NULL',
        Skill.value('NULL', 'VARCHAR(20)') AS 'NULL'
     FROM HR.Employees e2
     JOIN LATERAL e2.EmployeeData.nodes('/Employee/Skills/Skill') AS S(Skill)
     WHERE e2.EmployeeID = e.EmployeeID
     FOR XML PATH('Skill'), ROOT('Skills'), TYPE
    ) AS SkillsXML
FROM HR.Employees e
WHERE EmployeeData IS NOT NULL
LIMIT 20
