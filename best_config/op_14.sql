-- OP 14 Variant A (Direct translation): OPENJSON WITH -> SELECT json_extract from a scalar JSON column.
WITH sample AS (
    SELECT TransactionDetails AS doc
    FROM Sales.Transactions
    WHERE TransactionDetails IS NOT NULL
    LIMIT 1
)
SELECT
    json_extract(doc, '$.payment_method')::VARCHAR AS payment_method,
    json_extract(doc, '$.terms')::VARCHAR          AS terms,
    json_extract(doc, '$.discount_code')::VARCHAR  AS discount_code,
    json_extract(doc, '$.po_number')::VARCHAR       AS po_number,
    CAST(json_extract(doc, '$.processed') AS BOOLEAN) AS processed
FROM sample
LIMIT 20;
