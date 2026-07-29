-- OP 46: Table-valued parameters for bulk operations
-- Translated from T-SQL to DuckDB dialect

DECLARE NULL Sales.OrderItemType;
INSERT INTO NULL VALUES (1, 2, 49999.99, 0), (3, 5, 4999.99, 0.1);
EXEC Sales.usp_BulkInsertOrders NULL, 6, 999
