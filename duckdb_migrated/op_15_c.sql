-- OP 15 Variant C (Pre-computed/materialized): Assumes the order rows were already loaded
-- into a staging table Sales.StagedOrders(Product, Quantity, Price).
-- Schema (assumed):
--   CREATE TABLE Sales.StagedOrders (
--     Product VARCHAR, Quantity INTEGER, Price DECIMAL(18,2)
--   );
SELECT
    Product,
    Quantity,
    Price,
    Quantity * Price AS LineTotal
FROM Sales.StagedOrders;
