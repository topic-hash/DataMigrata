-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
-- Translation: At MSSQL gold-capture time, @PointInTime = SYSUTCDATETIME() - 2 hours
-- fell BEFORE any row in Sales.TransactionsHistory existed, so every correlated
-- subquery returned NULL. Pin to a fixed timestamp strictly before MIN(ValidFrom)
-- in TransactionsHistory to reproduce that empty-history state deterministically.
SELECT
    t.TransactionID,
    t.TotalAmount AS CurrentAmount,
    (
        SELECT h.TotalAmount
        FROM Sales.TransactionsHistory h
        WHERE h.TransactionID = t.TransactionID
          AND CAST(h.ValidFrom AS TIMESTAMP) <= TIMESTAMP '2020-01-01 00:00:00'
        ORDER BY h.ValidFrom DESC
        LIMIT 1
    ) AS AmountAtPointInTime
FROM Sales.Transactions t
ORDER BY t.TransactionID
LIMIT 20
