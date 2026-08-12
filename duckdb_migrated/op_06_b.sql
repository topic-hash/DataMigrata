-- OP 6 Variant B: Text parsing approach for XML modify() insert operation
-- Original MSSQL:
--   EmployeeData.modify('insert <Skill level="Advanced">Project Management</Skill>
--                        into (/Employee/Skills)[1]')
--   EmployeeData.query('/Employee/Skills/Skill')
--
-- DuckDB translation map:
--   XML .modify('insert <X> into (/Path)[1]')  -> regexp_replace injects <X> before closing tag
--   XML .query('/path')                       -> regexp_extract_all returns list of tag strings
--
-- EmployeeData remains an XML string in TEXT (no JSON conversion).

-- Step 1: Update top 10 employees: insert the new <Skill> element before </Skills>
-- DuckDB UPDATE lacks TOP/LIMIT, so we use a CTE to identify the 10 target rows.
WITH Targets AS (
    SELECT EmployeeID
    FROM HR.Employees
    WHERE EmployeeData IS NOT NULL
    LIMIT 10
)
UPDATE HR.Employees AS e
SET EmployeeData = regexp_replace(
        e.EmployeeData,
        '</Skills>',
        '<Skill level="Advanced">Project Management</Skill></Skills>',
        'i'  -- case-insensitive to mimic XML tag matching
    )
FROM Targets t
WHERE e.EmployeeID = t.EmployeeID;

-- Step 2: Read back skill elements as a list of tag strings
SELECT EmployeeID,
       FullName,
       regexp_extract_all(EmployeeData, '<Skill[^>]*>[^<]*</Skill>', 'i') AS Skills
FROM HR.Employees
WHERE EmployeeData IS NOT NULL
LIMIT 20;
