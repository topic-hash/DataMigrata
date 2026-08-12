-- OP 48: TRY_CONVERT with error handling for data type conversion
SELECT TOP 50
    TransactionID,
    TRY_CONVERT(INT, JSON_VALUE(TransactionDetails, '$.seats')) AS ParsedSeats,
    TRY_CONVERT(DECIMAL(18,2), JSON_VALUE(TransactionDetails, '$.discount_amount')) AS ParsedDiscount,
    TRY_CAST(JSON_VALUE(TransactionDetails, '$.processed') AS BIT) AS IsProcessed,
    IIF(TRY_CONVERT(INT, JSON_VALUE(TransactionDetails, '$.seats')) IS NULL, 'Invalid', 'Valid') AS ConversionStatus
FROM Sales.Transactions;
GO

