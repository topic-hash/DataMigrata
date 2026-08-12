-- OP 50 Variant A (Direct translation): CHANGETABLE -> return empty result set.
-- DuckDB has no built-in change tracking; return zero rows with a compatible schema.
SELECT
    CAST(NULL AS INTEGER)  AS ProductID,
    CAST(NULL AS BIGINT)   AS ChangeVersion,
    CAST(NULL AS VARCHAR)  AS Operation,
    CAST(NULL AS VARCHAR)  AS ProductName,
    CAST(NULL AS DECIMAL(18,2)) AS BasePrice
WHERE 1 = 0;
