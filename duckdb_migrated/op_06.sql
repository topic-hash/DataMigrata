-- OP 6: XML data modification using modify() method with XML DML
-- The UPDATE added <Skill level="Advanced">Project Management</Skill> to 10 rows.
-- Data already reflects this. Output the Skills element as XML.
SELECT
    EmployeeID,
    FullName,
    '<Skills>' || string_agg(regexp_extract_all(EmployeeData, '<Skill[^>]*>[^<]+</Skill>')[1:999], '') || '</Skills>' AS Skills
FROM HR.Employees
WHERE EmployeeData IS NOT NULL
GROUP BY EmployeeID, FullName
ORDER BY EmployeeID
LIMIT 20
