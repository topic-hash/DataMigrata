-- OP 22: Partitioned View across multiple tables
-- Translated from T-SQL to DuckDB dialect

SELECT * FROM Sales.vw_AllTransactions 
WHERE TransactionDate >= '2025-01-01'
ORDER BY TransactionDate DESC
LIMIT 50
