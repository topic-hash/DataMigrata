-- OP 7 Variant B: Text parsing approach for XML .nodes() CROSS APPLY shredding
-- Original MSSQL:
--   CROSS APPLY e.EmployeeData.nodes('/Employee/Skills/Skill') AS Skills(skill)
--   skill.value('@level', 'NVARCHAR(20)') AS SkillLevel
--   skill.value('.', 'NVARCHAR(100)') AS SkillName
--
-- DuckDB translation map:
--   XML .nodes('/path') CROSS APPLY  -> CROSS JOIN LATERAL UNNEST(generate_series)
--   XML .value('@level')            -> regexp_extract_all group 1 (attribute)
--   XML .value('.')                 -> regexp_extract_all group 1 (tag text)
--
-- EmployeeData remains an XML string in TEXT (no JSON conversion).
-- We extract two parallel arrays (levels and names) with capturing groups, then
-- zip them positionally using generate_series + LATERAL UNNEST.

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
       p.SkillLevels[i] AS SkillLevel,
       p.SkillNames[i]  AS SkillName
FROM Parsed p
CROSS JOIN LATERAL UNNEST(generate_series(1, len(p.SkillLevels))) AS t(i)
ORDER BY p.EmployeeID, SkillLevel
LIMIT 50;
