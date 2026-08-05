-- OP 39: Real-time operational analytics with columnstore
-- Translated from T-SQL to DuckDB dialect

SELECT Year, SUM(Amount) AS YearTotal, COUNT(*) AS TransactionCount
FROM Archive.OldTransactions 
GROUP BY Year 
ORDER BY Year
LIMIT 50
