-- OP 17: Temporal querying - BETWEEN
SELECT
    TransactionID,
    TotalAmount,
    ValidFrom,
    ValidTo,
    CASE
        WHEN ValidTo = '9999-12-31 23:59:59.9999999'::TIMESTAMP THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM Sales.Transactions
WHERE ValidFrom <= '2026-12-31'::TIMESTAMP
  AND ValidTo > '2026-01-01'::TIMESTAMP
ORDER BY TransactionID, ValidFrom
LIMIT 50
