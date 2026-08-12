-- OP 11: JSON path queries with lax/strict modes
SELECT
    TransactionID,
    json_extract_string(TransactionDetails, '$.payment_method') AS PaymentMethod,
    json_extract_string(TransactionDetails, '$.terms') AS Terms,
    CASE WHEN json_extract_string(TransactionDetails, '$.discount_code') IS NULL THEN NULL
         ELSE NULL END AS DiscountInfo,
    COALESCE(json_extract_string(TransactionDetails, '$.po_number'), 'N/A') AS PONumber,
    json_extract_string(TransactionDetails, '$.currency') AS Currency
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 50
