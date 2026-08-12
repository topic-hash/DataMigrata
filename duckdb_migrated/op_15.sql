-- OP 15: JSON array aggregation and decomposition
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT
    json_extract_string(t.elem, '$.product') AS Product,
    json_extract(t.elem, '$.qty') AS Quantity,
    json_extract(t.elem, '$.price') AS Price,
    json_extract(t.elem, '$.qty') * json_extract(t.elem, '$.price') AS LineTotal
FROM orders,
    LATERAL unnest(json_extract_array(j.j, '$')) AS t(elem)
