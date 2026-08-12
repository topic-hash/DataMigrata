-- OP 24: View with INSTEAD OF triggers for updatable complex views
SELECT * FROM Sales.vw_TransactionSummary
ORDER BY TransactionDate DESC
LIMIT 50
