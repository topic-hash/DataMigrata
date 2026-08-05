-- OP 6 Variant C: Pre-shredded relational table approach
-- Original MSSQL:
--   EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill> ...')
--   EmployeeData.query('/Employee/Skills/Skill')
--
-- Migration assumption: XML <Skills>/<Skill> nodes have been pre-shredded during
-- migration into a child table HR.EmployeeSkills with the following schema:
--   HR.EmployeeSkills(EmployeeID INT, SkillLevel VARCHAR(20), SkillName VARCHAR(100))
-- XML DML modify() becomes a relational INSERT; .query() becomes string_agg join.

-- Step 1: Insert one new skill row for each of the top 10 target employees
INSERT INTO HR.EmployeeSkills (EmployeeID, SkillLevel, SkillName)
SELECT EmployeeID, 'Advanced', 'Project Management'
FROM HR.Employees
WHERE EmployeeData IS NOT NULL
LIMIT 10;

-- Step 2: Re-aggregate skills per employee (mimics .query('/Employee/Skills/Skill'))
SELECT e.EmployeeID,
       e.FullName,
       string_agg(s.SkillLevel || ': ' || s.SkillName, ', ') AS Skills
FROM HR.Employees e
JOIN HR.EmployeeSkills s ON e.EmployeeID = s.EmployeeID
WHERE e.EmployeeData IS NOT NULL
GROUP BY e.EmployeeID, e.FullName
LIMIT 20;
