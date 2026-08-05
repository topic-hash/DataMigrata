-- OP 10 Variant A: JSON conversion of typed XML with XML schema collection
-- Original MSSQL:
--   DECLARE @typed XML;
--   SET @typed = '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>';
--   SELECT @typed.query('/Employee/Skills/Skill[@level="Expert"]');
--
-- DuckDB translation map:
--   DECLARE @typed XML; SET @typed = '...'  -> CTE returning JSON literal
--   Typed XML schema collection              -> JSON type (implicit structure)
--   @typed.query('/path[@attr="v"]')         -> json_extract + WHERE filter on
--                                               unnested array via json_extract_string
--
-- Migration assumption: typed XML documents are stored as JSON in DuckDB.
-- Shape: {"Employee": {"Skills": [{"level": "...", "name": "..."}]}}

WITH typed_json AS (
    SELECT '{
        "Employee": {
            "Skills": [
                {"level": "Expert", "name": "T-SQL"}
            ]
        }
    }'::JSON AS typed_doc
)
SELECT json_extract(t.typed_doc, '$.Employee.Skills') AS ExpertSkills
FROM typed_json t
WHERE EXISTS (
    SELECT 1
    FROM UNNEST(CAST(json_extract(t.typed_doc, '$.Employee.Skills') AS VARCHAR[])) AS s(skill)
    WHERE json_extract_string(skill::JSON, '$.level') = 'Expert'
);
