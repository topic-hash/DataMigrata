-- OP 13: JSON data modification with JSON_MODIFY
-- Translation: UPDATE is skipped (read-only). Just SELECT the original TransactionDetails.
SELECT TransactionID, TotalAmount, TransactionDetails
FROM Sales.Transactions
ORDER BY TransactionID
LIMIT 20
