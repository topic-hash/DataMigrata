-- OP 18: Temporal querying - CONTAINED IN
-- Translated from T-SQL to DuckDB dialect

SELECT     h.TransactionID, h.TotalAmount, h.ValidFrom, h.ValidTo,
    CAST(EPOCH(h.ValidTo) AS BIGINT) - CAST(EPOCH(h.ValidFrom) AS BIGINT) AS DurationSeconds
FROM Sales.TransactionsHistory h
WHERE h.ValidTo <> '9999-12-31 23:59:59.9999999'
ORDER BY h.ValidFrom DESC
LIMIT 50
