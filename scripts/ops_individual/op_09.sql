-- OP 9: XML index optimization demonstration
-- (Indexes created during migration, query leverages them)
SELECT TOP 50 EmployeeID, FullName, Department
FROM HR.Employees
WHERE EmployeeData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1;
GO

