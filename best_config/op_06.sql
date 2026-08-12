-- OP 6: XML data modification using modify() method with XML DML
-- Gold: output is the concatenated <Skill> elements (NO <Skills> wrapper)
-- Use LATERAL unnest + string_agg to concatenate list elements into a single string
SELECT
    e.EmployeeID,
    e.FullName,
    (SELECT string_agg(s, '') FROM unnest(regexp_extract_all(e.EmployeeData, '<Skill[^>]*>[^<]+</Skill>')) AS t(s)) AS Skills
FROM HR.Employees e
WHERE e.EmployeeData IS NOT NULL
ORDER BY e.EmployeeID
LIMIT 20
