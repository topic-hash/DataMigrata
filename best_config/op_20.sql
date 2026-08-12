-- OP 20: Temporal table with versioning analytics
-- Gold ordered by VersionCount DESC, TransactionID DESC
SELECT
    TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    date_diff('day', CAST(MIN(ValidFrom) AS TIMESTAMP), CAST(MAX(ValidFrom) AS TIMESTAMP)) AS LifespanDays
FROM (
    SELECT TransactionID, ValidFrom FROM Sales.Transactions
    UNION ALL
    SELECT TransactionID, ValidFrom FROM Sales.TransactionsHistory
) AS combined
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY VersionCount DESC, TransactionID DESC
LIMIT 50
