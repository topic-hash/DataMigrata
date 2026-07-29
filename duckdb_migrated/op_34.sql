-- OP 34: Spatial index query optimization
-- Translated from T-SQL to DuckDB dialect

SELECT TransactionID, TotalAmount
FROM Sales.Transactions WITH(INDEX(SIDX_Transactions_Region))
WHERE Region <= 10000000
LIMIT 50
