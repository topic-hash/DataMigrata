-- OP 14 Variant C (Pre-computed/materialized): Assumes a view Sales.vw_TransactionDetailsFlat
-- already exposes parsed JSON fields as columns.
-- Schema (assumed):
--   CREATE VIEW Sales.vw_TransactionDetailsFlat AS
--   SELECT TransactionID,
--          json_extract(TransactionDetails, '$.payment_method') AS payment_method,
--          json_extract(TransactionDetails, '$.terms')          AS terms,
--          json_extract(TransactionDetails, '$.discount_code')   AS discount_code,
--          json_extract(TransactionDetails, '$.po_number')       AS po_number,
--          CAST(json_extract(TransactionDetails, '$.processed') AS BOOLEAN) AS processed
--   FROM Sales.Transactions
--   WHERE TransactionDetails IS NOT NULL;

SELECT payment_method, terms, discount_code, po_number, processed
FROM Sales.vw_TransactionDetailsFlat
LIMIT 20;
