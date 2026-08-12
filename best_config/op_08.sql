-- OP 8 Variant A: JSON conversion of FOR XML PATH ... ROOT, TYPE
-- Original MSSQL:
--   SELECT TOP 20 EmployeeID, FullName,
--     (SELECT Skill.value('.', 'NVARCHAR(100)') AS '@name',
--             Skill.value('@level', 'NVARCHAR(20)') AS '@level'
--      FROM HR.Employees e2
--      CROSS APPLY e2.EmployeeData.nodes('/Employee/Skills/Skill') AS S(Skill)
--      WHERE e2.EmployeeID = e.EmployeeID
--      FOR XML PATH('Skill'), ROOT('Skills'), TYPE) AS SkillsXML
--   FROM HR.Employees e WHERE EmployeeData IS NOT NULL;
--
-- DuckDB translation map:
--   FOR XML PATH('Skill'), ROOT('Skills'), TYPE
--       -> json_object('Skills', json_group_array(json_object(...)))
--   XML .value('@attr', ...) -> json_extract_string(skill, '$.attr')
--   XML .value('.', ...)     -> json_extract_string(skill, '$.name')
--
-- Migration assumption: EmployeeData converted from XML to JSON string:
--   {"Employee": {"Skills": [{"level": "...", "name": "..."}]}}

SELECT e.EmployeeID,
       e.FullName,
       json_object(
           'Skills',
           json_group_array(
               json_object(
                   'name',  json_extract_string(skill_json::JSON, '$.name'),
                   'level', json_extract_string(skill_json::JSON, '$.level')
               )
           )
       ) AS SkillsXML
FROM HR.Employees e
CROSS JOIN LATERAL UNNEST(
    CAST(json_extract(e.EmployeeData::JSON, '$.Employee.Skills') AS VARCHAR[])
) AS t(skill_json)
WHERE e.EmployeeData IS NOT NULL
GROUP BY e.EmployeeID, e.FullName
LIMIT 20;
