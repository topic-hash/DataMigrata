-- OP 7 Variant C: Pre-shredded relational table approach
-- Original MSSQL:
--   CROSS APPLY e.EmployeeData.nodes('/Employee/Skills/Skill') AS Skills(skill)
--   skill.value('@level', 'NVARCHAR(20)') AS SkillLevel
--   skill.value('.', 'NVARCHAR(100)') AS SkillName
--
-- Migration assumption: XML <Skill> nodes pre-shredded into HR.EmployeeSkills:
--   HR.EmployeeSkills(EmployeeID INT, SkillLevel VARCHAR(20), SkillName VARCHAR(100))
-- XML .nodes() CROSS APPLY becomes a relational JOIN; .value() becomes column projection.

SELECT e.EmployeeID,
       e.FullName,
       s.SkillLevel,
       s.SkillName
FROM HR.Employees e
JOIN HR.EmployeeSkills s ON e.EmployeeID = s.EmployeeID
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, s.SkillLevel
LIMIT 50;
