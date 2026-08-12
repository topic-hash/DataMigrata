-- OP 7: XML shredding with nodes() method and cross apply
SELECT TOP 50
    e.EmployeeID,
    e.FullName,
    skill.value('@level', 'NVARCHAR(20)') AS SkillLevel,
    skill.value('.', 'NVARCHAR(100)') AS SkillName
FROM HR.Employees e
CROSS APPLY e.EmployeeData.nodes('/Employee/Skills/Skill') AS Skills(skill)
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel;
GO

