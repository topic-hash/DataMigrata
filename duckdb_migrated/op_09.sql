-- OP 9: XML index optimization demonstration
-- Translation: exist('/Employee/Skills/Skill[@level="Expert"]') → regex search
SELECT EmployeeID, FullName, Department
FROM HR.Employees
WHERE regexp_matches(EmployeeData, '<Skill level="Expert"')
ORDER BY EmployeeID
LIMIT 50
