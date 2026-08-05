-- OP 14 Variant B (Alternative approach): Treat the JSON document as a single-row table via unnest on a struct.
WITH sample AS (
    SELECT TransactionDetails AS doc
    FROM Sales.Transactions
    WHERE TransactionDetails IS NOT NULL
    LIMIT 1
),
parsed AS (
    SELECT (json_extract_struct(doc, '$')) AS s
    FROM sample
)
SELECT
    s.payment_method::VARCHAR  AS payment_method,
    s.terms::VARCHAR           AS terms,
    s.discount_code::VARCHAR   AS discount_code,
    s.po_number::VARCHAR       AS po_number,
    CAST(s.processed AS BOOLEAN) AS processed
FROM parsed
LIMIT 20;
