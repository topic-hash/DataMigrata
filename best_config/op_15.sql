-- OP 15: JSON array aggregation and decomposition
-- Use generate_series (UNION) + json_extract_string with index path
-- Note: j.j is interpreted as struct access in DuckDB — must use table alias (o.j)
WITH orders AS (
    SELECT CAST('[{"product":"Server","qty":2,"price":49999.99},{"product":"Agent","qty":5,"price":4999.99}]' AS JSON) AS j
),
nums AS (
    SELECT 0::BIGINT AS i UNION ALL SELECT 1::BIGINT
)
SELECT
    json_extract_string(o.j, '$[' || CAST(n.i AS VARCHAR) || '].product') AS Product,
    CAST(json_extract_string(o.j, '$[' || CAST(n.i AS VARCHAR) || '].qty') AS INTEGER) AS Quantity,
    CAST(json_extract_string(o.j, '$[' || CAST(n.i AS VARCHAR) || '].price') AS DECIMAL(18,2)) AS Price,
    CAST(json_extract_string(o.j, '$[' || CAST(n.i AS VARCHAR) || '].qty') AS INTEGER) * CAST(json_extract_string(o.j, '$[' || CAST(n.i AS VARCHAR) || '].price') AS DECIMAL(18,2)) AS LineTotal
FROM orders AS o, nums AS n
