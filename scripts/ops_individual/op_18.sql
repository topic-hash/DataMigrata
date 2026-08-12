-- OP 18: Temporal querying - CONTAINED IN
SELECT TOP 50
    h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    DATEDIFF(SECOND, h.ValidFrom, h.ValidTo) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.9999999'
ORDER BY h.ValidFrom DESC;
GO

