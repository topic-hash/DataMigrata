-- OP 13 Variant C (Pre-computed/materialized): Assumes an updatable view
-- Sales.vw_TransactionsTagged already exposes processed/tags columns and a trigger
-- (or DuckDB rule) rewrites the underlying JSON document.
-- Schema (assumed):
--   CREATE VIEW Sales.vw_TransactionsTagged AS
--   SELECT TransactionID, TotalAmount, TransactionDetails,
--          json_extract(TransactionDetails, '$.processed') AS processed,
--          json_extract(TransactionDetails, '$.tags')      AS tags
--   FROM Sales.Transactions;

-- Stage 1: mark un-processed as processed (limited to 100).
WITH target AS (
    SELECT TransactionID FROM Sales.vw_TransactionsTagged
    WHERE processed IS NULL LIMIT 100
)
UPDATE Sales.vw_TransactionsTagged SET processed = TRUE
WHERE TransactionID IN (SELECT TransactionID FROM target);

-- Stage 2: tag high-value (limited to 50).
WITH target AS (
    SELECT TransactionID FROM Sales.vw_TransactionsTagged
    WHERE TotalAmount > 50000 LIMIT 50
)
UPDATE Sales.vw_TransactionsTagged
SET tags = array_append(COALESCE(tags::VARCHAR[], ARRAY[]::VARCHAR[]), 'high_value')
WHERE TransactionID IN (SELECT TransactionID FROM target);

SELECT TransactionID, TotalAmount, TransactionDetails
FROM Sales.Transactions LIMIT 20;
