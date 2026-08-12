-- OP 15 Variant A (Direct translation): OPENJSON array -> unnest + json_extract.
WITH orders_json AS (
    SELECT '[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]'::JSON AS doc
),
rows AS (
    SELECT unnest(json_extract(doc, '$')) AS elem
    FROM orders_json
)
SELECT
    json_extract(elem, '$.product')::VARCHAR  AS Product,
    CAST(json_extract(elem, '$.qty')   AS INTEGER)   AS Quantity,
    CAST(json_extract(elem, '$.price') AS DECIMAL(18,2)) AS Price,
    CAST(json_extract(elem, '$.qty')   AS INTEGER) *
    CAST(json_extract(elem, '$.price') AS DECIMAL(18,2)) AS LineTotal
FROM rows;
