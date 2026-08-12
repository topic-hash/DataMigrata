-- OP 15: JSON array aggregation and decomposition
DECLARE @orders NVARCHAR(MAX) = '[
    {"product": "Server", "qty": 2, "price": 49999.99},
    {"product": "Agent", "qty": 5, "price": 4999.99}
]';

SELECT
    Product,
    Quantity,
    Price,
    Quantity * Price AS LineTotal
FROM OPENJSON(@orders)
WITH (
    Product NVARCHAR(100) '$.product',
    Quantity INT '$.qty',
    Price DECIMAL(18,2) '$.price'
);
GO

-- ============================================================================
-- CATEGORY 4: TEMPORAL TABLES (Operations 16-20)
-- ============================================================================

