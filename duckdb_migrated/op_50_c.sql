-- OP 50 Variant C (Pre-computed/materialized): Assumes a view Sales.vw_ProductChangeTable
-- already exposes the CHANGETABLE-compatible rows from the audit log.
-- Schema (assumed):
--   CREATE VIEW Sales.vw_ProductChangeTable AS
--   SELECT pc.ProductID, pc.ChangeVersion, pc.Operation, p.ProductName, p.BasePrice
--   FROM Audit.ProductChanges pc
--   LEFT JOIN Sales.Products p ON pc.ProductID = p.ProductID;

SELECT ProductID, ChangeVersion, Operation, ProductName, BasePrice
FROM Sales.vw_ProductChangeTable
LIMIT 50;
