-- OP 22: Partitioned View across multiple tables
SELECT TOP 50 * FROM Sales.vw_AllTransactions 
WHERE TransactionDate >= '2025-01-01'
ORDER BY TransactionDate DESC;
GO

