-- OP 18: Temporal querying - CONTAINED IN
SELECT
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    date_diff('second', CAST(h.ValidFrom AS TIMESTAMP), CAST(h.ValidTo AS TIMESTAMP)) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE CAST(h.ValidTo AS TIMESTAMP) <> '9999-12-31 23:59:59.9999999'::TIMESTAMP
ORDER BY h.ValidFrom DESC
LIMIT 50
