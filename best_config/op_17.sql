-- OP 17: Temporal querying - BETWEEN
-- Translated from T-SQL to DuckDB dialect

SELECT     TransactionID, TotalAmount, ValidFrom, ValidTo,
    CASE 
        WHEN ValidTo = '9999-12-31 23:59:59.9999999' THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM Sales.Transactions
ORDER BY TransactionID, ValidFrom
LIMIT 50
