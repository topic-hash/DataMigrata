-- OP 36: Columnstore index for analytical workloads
-- Compute AvgSales using floor(mul*1e8/count)/1e8 to TRUNCATE (not round) to 8 places
SELECT
    EmployeeID,
    CAST(SUM(TotalAmount) AS DECIMAL(36,8)) AS TotalSales,
    CAST(CAST(CAST(floor(CAST(SUM(TotalAmount) AS DECIMAL(38,8)) * 100000000 / COUNT(*)) AS BIGINT) AS DECIMAL(36,8)) / CAST(100000000 AS DECIMAL(36,8)) AS DECIMAL(36,8)) AS AvgSales,
    COUNT(*) AS TransactionCount,
    MAX(TransactionDate) AS LastTransaction
FROM Sales.Transactions
GROUP BY EmployeeID
ORDER BY TotalSales DESC
LIMIT 50
