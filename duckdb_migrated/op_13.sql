-- OP 13: JSON data modification with JSON_MODIFY
-- Translated from T-SQL to DuckDB dialect

UPDATE TOP (100) Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, '$.processed', CAST(1 AS BIT))
WHERE json_extract_string(TransactionDetails::JSON, '$.processed') IS NULL;
UPDATE TOP (50) Sales.Transactions
SET TransactionDetails = JSON_MODIFY(TransactionDetails, 'append $.tags', 'high_value')
WHERE TotalAmount > 50000;
SELECT TransactionID, TotalAmount, TransactionDetails FROM Sales.Transactions
LIMIT 20
