-- OP 50 Variant B (Alternative approach): Query a DuckDB-native audit log table populated by triggers.
-- Assumes Audit.ProductChanges(ProductID, ChangeVersion, Operation, ProductName, BasePrice, ChangedAt).
SELECT
    pc.ProductID,
    pc.ChangeVersion,
    pc.Operation,
    p.ProductName,
    p.BasePrice
FROM Audit.ProductChanges pc
LEFT JOIN Sales.Products p ON pc.ProductID = p.ProductID
ORDER BY pc.ChangeVersion DESC
LIMIT 50;
