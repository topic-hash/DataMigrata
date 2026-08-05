-- OP 9 Variant C: Pre-shredded relational table approach
-- Original MSSQL:
--   WHERE EmployeeData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1
--
-- Migration assumption: XML <Skill> nodes pre-shredded into HR.EmployeeSkills:
--   HR.EmployeeSkills(EmployeeID INT, SkillLevel VARCHAR(20), SkillName VARCHAR(100))
-- XML .exist() predicate becomes a simple WHERE on the child table; the EXISTS
-- semantics collapse into a semi-join. DISTINCT prevents duplicate rows when an
-- employee has multiple Expert skills.

SELECT DISTINCT e.EmployeeID,
       e.FullName,
       e.Department
FROM HR.Employees e
JOIN HR.EmployeeSkills s ON e.EmployeeID = s.EmployeeID
WHERE s.SkillLevel = 'Expert'
LIMIT 50;
