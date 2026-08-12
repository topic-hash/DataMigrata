-- OP 36: Columnstore index for analytical workloads
SELECT
    EmployeeID,
    CAST(SUM(TotalAmount) AS DECIMAL(36,8)) AS TotalSales,
    CAST(AVG(TotalAmount) AS DECIMAL(36,8)) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC
LIMIT 50
