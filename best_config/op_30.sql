-- OP 30: View with window functions and framing
-- Translated from T-SQL to DuckDB dialect

SELECT * FROM Sales.vw_RunningTotalsAndRanks 
ORDER BY FullName, TransactionDate
LIMIT 100;
-- ============================================================================
-- CATEGORY 6: SPATIAL DATA (Operations 31-35)
-- ============================================================================
