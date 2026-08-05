-- OP 9 Variant A: JSON conversion of XML .exist() predicate
-- Original MSSQL:
--   SELECT TOP 50 EmployeeID, FullName, Department
--   FROM HR.Employees
--   WHERE EmployeeData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1;
--
-- DuckDB translation map:
--   XML .exist('/path[@attr="v"]') = 1
--       -> EXISTS (SELECT 1 FROM UNNEST(json_array) WHERE json_extract_string = 'v')
--   XML index -> relies on DuckDB's zone maps / Adaptive Radix Tree indexes
--
-- Migration assumption: EmployeeData converted from XML to JSON string:
--   {"Employee": {"Skills": [{"level": "...", "name": "..."}]}}

SELECT e.EmployeeID,
       e.FullName,
       e.Department
FROM HR.Employees e
WHERE EXISTS (
    SELECT 1
    FROM UNNEST(
        CAST(json_extract(e.EmployeeData::JSON, '$.Employee.Skills') AS VARCHAR[])
    ) AS t(skill_json)
    WHERE json_extract_string(skill_json::JSON, '$.level') = 'Expert'
)
LIMIT 50;
