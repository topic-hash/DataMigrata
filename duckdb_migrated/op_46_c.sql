-- OP 46 Variant C (Pre-computed/materialized): Assumes a permanent staging table Sales.BulkOrderItems
-- and a DuckDB macro Sales.usp_BulkInsertOrders(employee_id, customer_id) inserts from it.
-- Schema (assumed):
--   CREATE TABLE Sales.BulkOrderItems(
--     ProductID INTEGER, Quantity INTEGER, UnitPrice DECIMAL(18,2), DiscountRate DECIMAL(18,2)
--   );
INSERT INTO Sales.BulkOrderItems (ProductID, Quantity, UnitPrice, DiscountRate)
VALUES (1, 2, 49999.99, 0.0), (3, 5, 4999.99, 0.1);

INSERT INTO Sales.Orders (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, DiscountRate)
SELECT 6, 999, ProductID, Quantity, UnitPrice, DiscountRate
FROM Sales.BulkOrderItems;
