-- OP 8 Variant C: Pre-shredded relational table approach
-- Original MSSQL:
--   FOR XML PATH('Skill'), ROOT('Skills'), TYPE
--   Skill.value('.', 'NVARCHAR(100)') AS '@name'
--   Skill.value('@level', 'NVARCHAR(20)') AS '@level'
--
-- Migration assumption: XML <Skill> nodes pre-shredded into HR.EmployeeSkills:
--   HR.EmployeeSkills(EmployeeID INT, SkillLevel VARCHAR(20), SkillName VARCHAR(100))
-- FOR XML PATH('Skill'), ROOT('Skills') aggregation becomes string_agg + concat
-- over the child rows.

SELECT e.EmployeeID,
       e.FullName,
       '<Skills>' ||
           string_agg(
               '<Skill level="' || s.SkillLevel || '">' || s.SkillName || '</Skill>',
               ''
           ) ||
       '</Skills>' AS SkillsXML
FROM HR.Employees e
JOIN HR.EmployeeSkills s ON e.EmployeeID = s.EmployeeID
WHERE e.EmployeeData IS NOT NULL
GROUP BY e.EmployeeID, e.FullName
LIMIT 20;
