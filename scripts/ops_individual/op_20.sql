-- OP 20: Temporal table with versioning analytics
SELECT TOP 50
    TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    DATEDIFF(DAY, MIN(ValidFrom), MAX(ValidFrom)) AS LifespanDays
FROM Sales.Transactions FOR SYSTEM_TIME ALL
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY VersionCount DESC;
GO

-- ============================================================================
-- CATEGORY 5: ADVANCED VIEWS (Operations 21-30)
-- ============================================================================

