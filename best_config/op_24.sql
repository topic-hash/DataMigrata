-- OP 24: View with INSTEAD OF triggers for updatable complex views
-- Cast AvgTransaction to DECIMAL(36,8) to match gold precision
SELECT
    TransactionDate,
    TransactionCount,
    CAST(DailyTotal AS DECIMAL(36,8)) AS DailyTotal,
    CAST(AvgTransaction AS DECIMAL(36,8)) AS AvgTransaction,
    ActiveEmployees
FROM Sales.vw_TransactionSummary
ORDER BY CAST(TransactionDate AS TIMESTAMP) DESC
LIMIT 50
