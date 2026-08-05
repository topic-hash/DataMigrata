-- OP 8 Variant B: Text parsing approach for FOR XML PATH aggregation
-- Original MSSQL:
--   FOR XML PATH('Skill'), ROOT('Skills'), TYPE
--   Skill.value('.', 'NVARCHAR(100)') AS '@name'
--   Skill.value('@level', 'NVARCHAR(20)') AS '@level'
--
-- DuckDB translation map:
--   FOR XML PATH('Skill'), ROOT('Skills')
--       -> '<Skills>' || string_agg('<Skill ...>...</Skill>', '') || '</Skills>'
--   XML .value('@attr')  -> regexp_extract_all group 1 (attribute)
--   XML .value('.')      -> regexp_extract_all group 1 (tag text)
--
-- EmployeeData remains an XML string in TEXT (no JSON conversion).
-- We capture the level attribute and the tag text per <Skill>, then rebuild the
-- XML fragment using string_agg.

WITH Parsed AS (
    SELECT
        e.EmployeeID,
        e.FullName,
        regexp_extract_all(e.EmployeeData, '<Skill\s+level="([^"]+)"', 1) AS SkillLevels,
        regexp_extract_all(e.EmployeeData, '<Skill[^>]*>([^<]+)</Skill>', 1) AS SkillNames
    FROM HR.Employees e
    WHERE e.EmployeeData IS NOT NULL
)
SELECT p.EmployeeID,
       p.FullName,
       '<Skills>' ||
           string_agg(
               '<Skill level="' || p.SkillLevels[i] || '">' || p.SkillNames[i] || '</Skill>',
               ''
           ) ||
       '</Skills>' AS SkillsXML
FROM Parsed p
CROSS JOIN LATERAL UNNEST(generate_series(1, len(p.SkillLevels))) AS t(i)
GROUP BY p.EmployeeID, p.FullName
LIMIT 20;
