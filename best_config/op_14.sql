-- OP 14: OpenJSON with explicit schema for table-valued parsing
SELECT
    json_extract_string(j.TransactionDetails, '$.payment_method') AS payment_method,
    json_extract_string(j.TransactionDetails, '$.terms') AS terms,
    json_extract_string(j.TransactionDetails, '$.discount_code') AS discount_code,
    json_extract_string(j.TransactionDetails, '$.po_number') AS po_number,
    CASE WHEN json_extract_string(j.TransactionDetails, '$.processed') = 'true' THEN 1
         WHEN json_extract_string(j.TransactionDetails, '$.processed') = 'false' THEN 0
         ELSE NULL END AS processed
FROM (
    SELECT TransactionDetails
    FROM Sales.Transactions
    WHERE TransactionDetails IS NOT NULL
    ORDER BY TransactionID
    LIMIT 1
) AS j
