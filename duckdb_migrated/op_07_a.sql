-- OP 7 Variant A: JSON conversion of XML .nodes() CROSS APPLY shredding
-- Original MSSQL:
--   SELECT TOP 50 e.EmployeeID, e.FullName,
--        skill.value('@level', 'NVARCHAR(20)') AS SkillLevel,
--        skill.value('.', 'NVARCHAR(100)') AS SkillName
--   FROM HR.Employees e
--   CROSS APPLY e.EmployeeData.nodes('/Employee/Skills/Skill') AS Skills(skill)
--   WHERE e.EmployeeData IS NOT NULL
--   ORDER BY e.EmployeeID, SkillLevel;
--
-- DuckDB translation map:
--   XML .nodes('/path') CROSS APPLY  -> CROSS JOIN LATERAL UNNEST(json array)
--   XML .value('@attr', 'NVARCHAR')   -> json_extract_string(skill, '$.attr')
--   XML .value('.', 'NVARCHAR')      -> json_extract_string(skill, '$.name')
--
-- Migration assumption: EmployeeData converted from XML to JSON string:
--   {"Employee": {"Skills": [{"level": "...", "name": "..."}]}}

SELECT e.EmployeeID,
       e.FullName,
       json_extract_string(skill_json::JSON, '$.level') AS SkillLevel,
       json_extract_string(skill_json::JSON, '$.name')  AS SkillName
FROM HR.Employees e
CROSS JOIN LATERAL UNNEST(
    CAST(json_extract(e.EmployeeData::JSON, '$.Employee.Skills') AS VARCHAR[])
) AS t(skill_json)
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID, SkillLevel
LIMIT 50;
