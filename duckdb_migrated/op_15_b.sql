-- OP 15 Variant B (Alternative approach): Convert the JSON array to a struct list via json_extract_struct and unnest.
WITH orders_json AS (
    SELECT '[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]'::JSON AS doc
),
parsed AS (
    SELECT unnest(json_extract_struct(doc, '$')) AS s
    FROM orders_json
)
SELECT
    s.product::VARCHAR         AS Product,
    CAST(s.qty   AS INTEGER)   AS Quantity,
    CAST(s.price AS DECIMAL(18,2)) AS Price,
    CAST(s.qty   AS INTEGER) * CAST(s.price AS DECIMAL(18,2)) AS LineTotal
FROM parsed;
