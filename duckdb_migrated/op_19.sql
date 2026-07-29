-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
-- Translated from T-SQL to DuckDB dialect

SELECT     t.TransactionID,
    t.TotalAmount AS CurrentAmount,
    (SELECT TOP 1 h.TotalAmount 
     FROM Sales.TransactionsHistory h 
     WHERE h.TransactionID = t.TransactionID 
     AND h.ValidFrom <= CURRENT_TIMESTAMP
     ORDER BY h.ValidFrom DESC) AS AmountAtPointInTime
FROM Sales.Transactions t
LIMIT 20
