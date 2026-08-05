-- OP 48 Variant C (Pre-computed/materialized): Assumes a view Sales.vw_TransactionParsedFields
-- already exposes typed parsed columns.
-- Schema (assumed):
--   CREATE VIEW Sales.vw_TransactionParsedFields AS
--   SELECT TransactionID,
--          TRY_CAST(json_extract(TransactionDetails, '$.seats') AS INTEGER) AS ParsedSeats,
--          TRY_CAST(json_extract(TransactionDetails, '$.discount_amount') AS DECIMAL(18,2)) AS ParsedDiscount,
--          TRY_CAST(json_extract(TransactionDetails, '$.processed') AS BOOLEAN) AS IsProcessed
--   FROM Sales.Transactions;

SELECT
    TransactionID,
    ParsedSeats,
    ParsedDiscount,
    IsProcessed,
    CASE WHEN ParsedSeats IS NULL THEN 'Invalid' ELSE 'Valid' END AS ConversionStatus
FROM Sales.vw_TransactionParsedFields
LIMIT 50;
