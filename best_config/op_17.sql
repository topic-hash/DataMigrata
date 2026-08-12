-- OP 17: Temporal querying - BETWEEN
-- Gold includes both historical (from TransactionsHistory) and current (from Transactions) rows
SELECT
    TransactionID,
    TotalAmount,
    ValidFrom,
    ValidTo,
    CASE
        WHEN CAST(ValidTo AS TIMESTAMP) = '9999-12-31 23:59:59.9999999'::TIMESTAMP THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM (
    SELECT TransactionID, TotalAmount, ValidFrom, ValidTo FROM Sales.Transactions
    UNION ALL
    SELECT TransactionID, TotalAmount, ValidFrom, ValidTo FROM Sales.TransactionsHistory
) combined
WHERE CAST(ValidFrom AS TIMESTAMP) <= '2026-12-31'::TIMESTAMP
  AND CAST(ValidTo AS TIMESTAMP) > '2026-01-01'::TIMESTAMP
ORDER BY TransactionID, ValidFrom
LIMIT 50
