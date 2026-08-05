-- OP 10 Variant C: Pre-shredded relational approach for typed XML
-- Original MSSQL:
--   DECLARE @typed XML;
--   SET @typed = '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>';
--   SELECT @typed.query('/Employee/Skills/Skill[@level="Expert"]');
--
-- Migration assumption: Typed XML schema collections map to typed tables in DuckDB.
-- A schema-valid literal becomes a single-row VALUES expression conforming to the
-- relational schema (SkillLevel, SkillName). The .query() filter becomes a WHERE.
-- Schema: HR.TypedEmployeeSkills(SkillLevel VARCHAR(20), SkillName VARCHAR(100))

WITH typed_skills (SkillLevel, SkillName) AS (
    VALUES ('Expert', 'T-SQL')
)
SELECT SkillName AS ExpertSkill
FROM typed_skills
WHERE SkillLevel = 'Expert';
