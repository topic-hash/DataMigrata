-- OP 48 Variant B (Alternative approach): Pre-extract JSON values into a CTE, then TRY_CAST once.
WITH extracted AS (
    SELECT
        TransactionID,
        json_extract(TransactionDetails, '$.seats')           AS seats_raw,
        json_extract(TransactionDetails, '$.discount_amount') AS discount_raw,
        json_extract(TransactionDetails, '$.processed')       AS processed_raw
    FROM Sales.Transactions
    LIMIT 50
)
SELECT
    TransactionID,
    TRY_CAST(seats_raw     AS INTEGER)    AS ParsedSeats,
    TRY_CAST(discount_raw  AS DECIMAL(18,2)) AS ParsedDiscount,
    TRY_CAST(processed_raw AS BOOLEAN)    AS IsProcessed,
    CASE WHEN TRY_CAST(seats_raw AS INTEGER) IS NULL THEN 'Invalid' ELSE 'Valid' END AS ConversionStatus
FROM extracted;
