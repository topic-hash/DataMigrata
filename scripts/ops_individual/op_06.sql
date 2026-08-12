-- OP 6: XML data modification using modify() method with XML DML
UPDATE TOP (10) HR.Employees
SET EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill> 
                         into (/Employee/Skills)[1]')
WHERE EmployeeData IS NOT NULL;

SELECT TOP 20 EmployeeID, FullName, EmployeeData.query('/Employee/Skills/Skill') AS Skills
FROM HR.Employees WHERE EmployeeData IS NOT NULL;
GO

