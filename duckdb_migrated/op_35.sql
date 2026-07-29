-- OP 35: Multi-polygon territory analysis
-- Translated from T-SQL to DuckDB dialect

SELECT     t.TransactionID,
    t.TotalAmount,
    NULL= TRUE AS IsInTerritory
FROM Sales.Transactions t
WHERE t.Region IS NOT NULL
LIMIT 50;
-- ============================================================================
-- CATEGORY 7: COLUMNSTORE & IN-MEMORY (Operations 36-40)
-- ============================================================================
