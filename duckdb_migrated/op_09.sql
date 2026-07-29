-- OP 9: XML index optimization demonstration
-- Translated from T-SQL to DuckDB dialect

-- (Indexes created during migration, query leverages them)
SELECT EmployeeID, FullName, Department
FROM HR.Employees
WHERE EmployeeData.exist('/Employee/Skills/Skill[NULL="Expert"]') = 1
LIMIT 50
