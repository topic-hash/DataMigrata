-- OP 24: View with INSTEAD OF triggers for updatable complex views
-- vw_TransactionSummary and trigger created during migration
SELECT TOP 50 * FROM Sales.vw_TransactionSummary
ORDER BY TransactionDate DESC;
GO

