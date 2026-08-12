-- OP 19: Temporal data reconstruction (point-in-time recovery simulation)
DECLARE @PointInTime DATETIME2 = DATEADD(HOUR, -2, SYSUTCDATETIME());

SELECT TOP 20
    t.TransactionID,
    t.TotalAmount AS CurrentAmount,
    (SELECT TOP 1 h.TotalAmount 
     FROM Sales.TransactionsHistory h 
     WHERE h.TransactionID = t.TransactionID 
     AND h.ValidFrom <= @PointInTime
     ORDER BY h.ValidFrom DESC) AS AmountAtPointInTime
FROM Sales.Transactions t;
GO

