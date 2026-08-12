-- OP 46 Variant A (Direct translation): TVP -> unnest array of structs.
-- The MSSQL TVP @items has columns (ProductID, Quantity, UnitPrice, DiscountRate).
-- Replace with a DuckDB VALUES list joined to the target insert via a CTE.
WITH source_items AS (
    SELECT * FROM (VALUES
        (1, 2, 49999.99, 0.0),
        (3, 5, 4999.99,  0.1)
    ) AS t(ProductID, Quantity, UnitPrice, DiscountRate)
)
-- Bulk insert into Sales.Orders (assumes columns EmployeeID/CustomerID, ProductID, Quantity, UnitPrice, DiscountRate).
INSERT INTO Sales.Orders (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, DiscountRate)
SELECT 6, 999, ProductID, Quantity, UnitPrice, DiscountRate
FROM source_items;
