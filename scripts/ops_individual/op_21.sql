-- OP 21: Indexed (Materialized) View with SCHEMABINDING and aggregation
-- Already created during migration; query it directly
SELECT * FROM Sales.vw_ProductSummary
ORDER BY Category;
GO

