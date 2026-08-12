-- OP 16: Temporal querying - AS OF
-- Translated from T-SQL to DuckDB dialect

SELECT     TransactionID, EmployeeID, TotalAmount, TransactionDate,
    ValidFrom, ValidTo
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 50
