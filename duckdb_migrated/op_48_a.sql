-- OP 48 Variant A (Direct translation): TRY_CONVERT(type, expr) -> TRY_CAST(expr AS type).
SELECT
    TransactionID,
    TRY_CAST(json_extract(TransactionDetails, '$.seats') AS INTEGER)    AS ParsedSeats,
    TRY_CAST(json_extract(TransactionDetails, '$.discount_amount') AS DECIMAL(18,2)) AS ParsedDiscount,
    TRY_CAST(json_extract(TransactionDetails, '$.processed') AS BOOLEAN) AS IsProcessed,
    CASE
        WHEN TRY_CAST(json_extract(TransactionDetails, '$.seats') AS INTEGER) IS NULL
            THEN 'Invalid'
        ELSE 'Valid'
    END AS ConversionStatus
FROM Sales.Transactions
LIMIT 50;
