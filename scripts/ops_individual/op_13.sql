-- OP 13: JSON data modification with JSON_MODIFY
UPDATE TOP (100) Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, '$.processed', CAST(1 AS BIT))
WHERE JSON_VALUE(TransactionDetails, '$.processed') IS NULL;

UPDATE TOP (50) Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, 'append $.tags', 'high_value')
WHERE TotalAmount > 50000;

SELECT TOP 20 TransactionID, TotalAmount, TransactionDetails FROM Sales.Transactions;
GO

