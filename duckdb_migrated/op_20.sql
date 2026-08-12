-- OP 20: Temporal table with versioning analytics
SELECT
    TransactionID,
    COUNT(*) AS VersionCount,
    MIN(ValidFrom) AS FirstVersion,
    MAX(ValidFrom) AS LastVersion,
    datediff('day', MIN(ValidFrom), MAX(ValidFrom)) AS LifespanDays
FROM (
    SELECT TransactionID, ValidFrom FROM Sales.Transactions
    UNION ALL
    SELECT TransactionID, ValidFrom FROM Sales.TransactionsHistory
) AS combined
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY VersionCount DESC, TransactionID
LIMIT 50
