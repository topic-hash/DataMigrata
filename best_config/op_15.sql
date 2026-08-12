-- OP 15: JSON array aggregation and decomposition
-- Use generate_series + json_extract with index path to iterate array elements
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT
    json_extract_string(j.j, '$[' || i || '].product') AS Product,
    CAST(json_extract_string(j.j, '$[' || i || '].qty') AS INTEGER) AS Quantity,
    CAST(json_extract_string(j.j, '$[' || i || '].price') AS DECIMAL(18,2)) AS Price,
    CAST(json_extract_string(j.j, '$[' || i || '].qty') AS INTEGER) * CAST(json_extract_string(j.j, '$[' || i || '].price') AS DECIMAL(18,2)) AS LineTotal
FROM orders,
    generate_series(0::BIGINT, CAST(json_array_length(j.j) - 1 AS BIGINT)) AS t(i)
