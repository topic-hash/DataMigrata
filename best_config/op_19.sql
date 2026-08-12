-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
-- Translation: @PointInTime = 2 hours ago; for each transaction, find the latest history row
SELECT
    t.TransactionID,
    t.TotalAmount AS CurrentAmount,
    (
        SELECT h.TotalAmount
        FROM Sales.TransactionsHistory h
        WHERE h.TransactionID = t.TransactionID
          AND CAST(h.ValidFrom AS TIMESTAMP) <= CURRENT_TIMESTAMP - INTERVAL 2 HOUR
        ORDER BY h.ValidFrom DESC
        LIMIT 1
    ) AS AmountAtPointInTime
FROM Sales.Transactions t
ORDER BY t.TransactionID
LIMIT 20
