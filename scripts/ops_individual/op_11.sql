-- OP 11: JSON path queries with lax/strict modes
SELECT TOP 50
    TransactionID,
    JSON_VALUE(TransactionDetails, '$.payment_method') AS PaymentMethod,
    JSON_VALUE(TransactionDetails, '$.terms') AS Terms,
    JSON_QUERY(TransactionDetails, '$.discount_code') AS DiscountInfo,
    ISNULL(JSON_VALUE(TransactionDetails, '$.po_number'), 'N/A') AS PONumber,
    JSON_VALUE(TransactionDetails, '$.currency') AS Currency
FROM Sales.Transactions;
GO

