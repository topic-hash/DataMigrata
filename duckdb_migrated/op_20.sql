-- OP 20: Temporal table with versioning analytics
-- Translated from T-SQL to DuckDB dialect

SELECT     TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    DATE_DIFF('day', MIN(ValidFrom), MAX(ValidFrom)) AS LifespanDays
FROM Sales.Transactions
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY VersionCount DESC
LIMIT 50;
-- ============================================================================
-- CATEGORY 5: ADVANCED VIEWS (Operations 21-30)
-- ============================================================================
