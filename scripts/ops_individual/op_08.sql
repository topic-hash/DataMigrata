-- OP 8: XML aggregation using FOR XML EXPLICIT with TYPE directive
SELECT TOP 20
    EmployeeID,
    FullName,
    (SELECT 
        Skill.value('.', 'NVARCHAR(100)') AS '@name',
        Skill.value('@level', 'NVARCHAR(20)') AS '@level'
     FROM HR.Employees e2
     CROSS APPLY e2.EmployeeData.nodes('/Employee/Skills/Skill') AS S(Skill)
     WHERE e2.EmployeeID = e.EmployeeID
     FOR XML PATH('Skill'), ROOT('Skills'), TYPE
    ) AS SkillsXML
FROM HR.Employees e
WHERE EmployeeData IS NOT NULL;
GO

