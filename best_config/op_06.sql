-- OP 6 Variant A: JSON conversion of XML modify() insert operation
-- Original MSSQL:
--   UPDATE TOP (10) HR.Employees
--   SET EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill>
--                            into (/Employee/Skills)[1]')
--   WHERE EmployeeData IS NOT NULL;
--   SELECT TOP 20 EmployeeID, FullName, EmployeeData.query('/Employee/Skills/Skill') AS Skills
--   FROM HR.Employees WHERE EmployeeData IS NOT NULL;
--
-- DuckDB translation map:
--   XML .modify('insert ... into ...')  -> UPDATE with json_set + json_array_append
--   XML .query('/path')                 -> json_extract (returns JSON sub-tree)
--   Typed XML schema collection         -> JSON type
--
-- Migration assumption: EmployeeData (TEXT) has been converted from XML string to
-- JSON string during migration, e.g. shape is:
--   {"Employee": {"Skills": [{"level": "...", "name": "..."}]}}

-- Step 1: Update top 10 employees by appending a new skill object to the Skills array.
-- DuckDB UPDATE lacks TOP/LIMIT, so we identify targets via a CTE and join in FROM.
WITH Targets AS (
    SELECT EmployeeID
    FROM HR.Employees
    WHERE EmployeeData IS NOT NULL
    LIMIT 10
)
UPDATE HR.Employees AS e
SET EmployeeData = json_set(
        e.EmployeeData::JSON,
        '$.Employee.Skills',
        json_array_append(
            COALESCE(json_extract(e.EmployeeData::JSON, '$.Employee.Skills'), '[]'::JSON),
            json_object('level', 'Advanced', 'name', 'Project Management')
        )
    )::TEXT
FROM Targets t
WHERE e.EmployeeID = t.EmployeeID;

-- Step 2: Read back the skills JSON array (replaces .query('/Employee/Skills/Skill'))
SELECT EmployeeID,
       FullName,
       json_extract(EmployeeData::JSON, '$.Employee.Skills') AS Skills
FROM HR.Employees
WHERE EmployeeData IS NOT NULL
LIMIT 20;
