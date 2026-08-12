-- OP 22: Partitioned View across multiple tables
SELECT * FROM Sales.vw_AllTransactions
WHERE TransactionDate >= '2025-01-01'::TIMESTAMP
ORDER BY TransactionDate DESC, TransactionID DESC
LIMIT 50
