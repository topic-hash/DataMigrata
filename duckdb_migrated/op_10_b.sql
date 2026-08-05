-- OP 10 Variant B: Text parsing approach for typed XML query
-- Original MSSQL:
--   DECLARE @typed XML;
--   SET @typed = '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>';
--   SELECT @typed.query('/Employee/Skills/Skill[@level="Expert"]');
--
-- DuckDB translation map:
--   DECLARE @typed XML; SET @typed = '...'  -> CTE returning XML-string literal
--   @typed.query('/path[@attr="v"]')         -> regexp_extract with pattern matching
--                                               both the tag and the attribute filter
--
-- EmployeeData remains an XML string (no JSON conversion). The schema collection
-- contract is preserved at the application layer; DuckDB treats the value as TEXT.

WITH typed_xml AS (
    SELECT '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>' AS typed_doc
)
SELECT regexp_extract(t.typed_doc, '<Skill\s+level="Expert">[^<]*</Skill>', 0) AS ExpertSkillElement
FROM typed_xml t;
