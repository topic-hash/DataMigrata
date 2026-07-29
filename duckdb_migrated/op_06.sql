-- OP 6: XML data modification using modify() method with XML DML
-- Translated from T-SQL to DuckDB dialect

UPDATE TOP (10) HR.Employees
SET EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill> 
                         into (/Employee/Skills)"1"')
WHERE EmployeeData IS NOT NULL;
SELECT EmployeeID, FullName, EmployeeData.query('/Employee/Skills/Skill') AS Skills
FROM HR.Employees WHERE EmployeeData IS NOT NULL
LIMIT 20
