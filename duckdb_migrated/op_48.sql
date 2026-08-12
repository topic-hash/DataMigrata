-- OP 48: TRY_CONVERT with error handling for data type conversion
-- Translation: TRY_CONVERT → TRY_CAST; JSON_VALUE → json_extract_string
SELECT
    TransactionID,
    TRY_CAST(json_extract_string(TransactionDetails, '$.seats') AS INTEGER) AS ParsedSeats,
    TRY_CAST(json_extract_string(TransactionDetails, '$.discount_amount') AS DECIMAL(18,2)) AS ParsedDiscount,
    TRY_CAST(json_extract_string(TransactionDetails, '$.processed') AS BOOLEAN) AS IsProcessed,
    CASE
        WHEN TRY_CAST(json_extract_string(TransactionDetails, '$.seats') AS INTEGER) IS NULL THEN 'Invalid'
        ELSE 'Valid'
    END AS ConversionStatus
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 50
