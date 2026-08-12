-- OP 18: Temporal querying - CONTAINED IN
SELECT
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    datediff('second', h.ValidFrom, h.ValidTo) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.9999999'::TIMESTAMP
ORDER BY h.ValidFrom DESC
LIMIT 50
