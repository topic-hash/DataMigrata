-- OP 24: View with INSTEAD OF triggers for updatable complex views
-- Translated from T-SQL to DuckDB dialect

-- vw_TransactionSummary and trigger created during migration
SELECT * FROM Sales.vw_TransactionSummary
ORDER BY TransactionDate DESC
LIMIT 50
