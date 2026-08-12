-- OP 15: JSON array aggregation and decomposition
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT
    json_extract_string(t.elem, '$.product') AS Product,
    CAST(json_extract_string(t.elem, '$.qty') AS INTEGER) AS Quantity,
    CAST(json_extract_string(t.elem, '$.price') AS DECIMAL(18,2)) AS Price,
    CAST(json_extract_string(t.elem, '$.qty') AS INTEGER) * CAST(json_extract_string(t.elem, '$.price') AS DECIMAL(18,2)) AS LineTotal
FROM orders,
    LATERAL unnest(json_extract(j.j, '$')::JSON[]) AS t(elem)
