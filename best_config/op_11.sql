-- OP 11: JSON path queries with lax/strict modes
-- Translated from T-SQL to DuckDB dialect

SELECT     TransactionID,
    json_extract_string(TransactionDetails::JSON, '$.payment_method') AS PaymentMethod,
    json_extract_string(TransactionDetails::JSON, '$.terms') AS Terms,
    json_extract(TransactionDetails::JSON, '$.discount_code') AS DiscountInfo,
    COALESCE(json_extract_string(TransactionDetails::JSON, '$.po_number'), 'N/A') AS PONumber,
    json_extract_string(TransactionDetails::JSON, '$.currency') AS Currency
FROM Sales.Transactions
LIMIT 50
