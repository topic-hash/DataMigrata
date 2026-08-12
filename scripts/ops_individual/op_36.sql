-- OP 36: Columnstore index for analytical workloads
SELECT TOP 50
    EmployeeID,
    SUM(TotalAmount) AS TotalSales,
    AVG(TotalAmount) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC;
GO

