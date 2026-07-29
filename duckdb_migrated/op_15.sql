-- OP 15: JSON array aggregation and decomposition
-- Translated from T-SQL to DuckDB dialect

SELECT
    Product,
    Quantity,
    Price,
    Quantity * Price AS LineTotal
FROM OPENJSON(NULL)
WITH (
    Product VARCHAR(100) '$.product',
    Quantity INT '$.qty',
    Price DECIMAL(18,2) '$.price'
);
-- ============================================================================
-- CATEGORY 4: TEMPORAL TABLES (Operations 16-20)
-- ============================================================================
