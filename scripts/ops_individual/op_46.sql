-- OP 46: Table-valued parameters for bulk operations
DECLARE @items Sales.OrderItemType;
INSERT INTO @items VALUES (1, 2, 49999.99, 0), (3, 5, 4999.99, 0.1);
EXEC Sales.usp_BulkInsertOrders @items, 6, 999;
GO

