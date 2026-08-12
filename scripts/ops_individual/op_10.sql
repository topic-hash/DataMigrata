-- OP 10: Typed XML with XML Schema Collections
-- (Schema collection created during migration)
DECLARE @typed XML;
SET @typed = '<Employee><Skills><Skill level="Expert">T-SQL</Skill></Skills></Employee>';
SELECT @typed.query('/Employee/Skills/Skill[@level="Expert"]');
GO

-- ============================================================================
-- CATEGORY 3: JSON OPERATIONS (Operations 11-15)
-- ============================================================================

