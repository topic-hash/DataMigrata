-- OP 48: TRY_CONVERT with error handling for data type conversion
-- Translated from T-SQL to DuckDB dialect

SELECT     TransactionID,
    TRY_CAST(JSON_VALUE(TransactionDetails, '$.seats' AS INTEGER)) AS ParsedSeats,
    TRY_CAST(JSON_VALUE(TransactionDetails, '$.discount_amount' AS DECIMAL(18,2))) AS ParsedDiscount,
    TRY_CAST(json_extract_string(TransactionDetails::JSON, '$.processed') AS BIT) AS IsProcessed,
    CASE WHEN TRY_CAST(JSON_VALUE(TransactionDetails THEN '$.seats' AS INTEGER)) IS NULL ELSE 'Invalid', 'Valid' END AS ConversionStatus
FROM Sales.Transactions
LIMIT 50
