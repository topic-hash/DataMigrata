-- OP 46 Variant B (Alternative approach): Use a temporary staging table populated from JSON array.
CREATE OR REPLACE TEMP TABLE staging_items (
    ProductID INTEGER, Quantity INTEGER, UnitPrice DECIMAL(18,2), DiscountRate DECIMAL(18,2)
);
INSERT INTO staging_items
SELECT
    CAST(json_extract(elem, '$.ProductID') AS INTEGER),
    CAST(json_extract(elem, '$.Quantity')  AS INTEGER),
    CAST(json_extract(elem, '$.UnitPrice') AS DECIMAL(18,2)),
    CAST(json_extract(elem, '$.DiscountRate') AS DECIMAL(18,2))
FROM (
    SELECT unnest(json_extract('[
        {"ProductID": 1, "Quantity": 2, "UnitPrice": 49999.99, "DiscountRate": 0.0},
        {"ProductID": 3, "Quantity": 5, "UnitPrice": 4999.99,  "DiscountRate": 0.1}
    ]'::JSON, '$')) AS elem
);

INSERT INTO Sales.Orders (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, DiscountRate)
SELECT 6, 999, ProductID, Quantity, UnitPrice, DiscountRate
FROM staging_items;
