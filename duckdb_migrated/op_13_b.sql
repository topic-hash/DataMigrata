-- OP 13 Variant B (Alternative approach): Rebuild JSON via json_object instead of mutating in place.
-- Produces a fresh document with desired fields merged.
WITH to_update AS (
    SELECT TransactionID, TransactionDetails
    FROM Sales.Transactions
    WHERE json_extract(TransactionDetails, '$.processed') IS NULL
    LIMIT 100
)
UPDATE Sales.Transactions
SET TransactionDetails = json_object(
    'payment_method', json_extract(TransactionDetails, '$.payment_method'),
    'terms',          json_extract(TransactionDetails, '$.terms'),
    'discount_code',  json_extract(TransactionDetails, '$.discount_code'),
    'po_number',      json_extract(TransactionDetails, '$.po_number'),
    'processed',     TRUE
)
WHERE TransactionID IN (SELECT TransactionID FROM to_update);

WITH to_tag AS (
    SELECT TransactionID, TransactionDetails
    FROM Sales.Transactions
    WHERE TotalAmount > 50000
    LIMIT 50
)
UPDATE Sales.Transactions
SET TransactionDetails = json_insert(
    TransactionDetails, '$.tags', ['high_value'], true
)
WHERE TransactionID IN (SELECT TransactionID FROM to_tag);

SELECT TransactionID, TotalAmount, TransactionDetails
FROM Sales.Transactions
LIMIT 20;
