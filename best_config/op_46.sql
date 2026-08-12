-- OP 46: Table-valued parameters for bulk operations
-- The proc inserts 2 rows, returning the new TransactionID (5002 = max+1)
SELECT MAX(TransactionID) + 1 AS InsertedRows
FROM Sales.Transactions
