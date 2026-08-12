-- OP 40: Batch mode on rowstore
SELECT
    EmployeeID,
    FullName,
    CAST(TotalSales AS DECIMAL(36,8)) AS TotalSales,
    COUNT(*) OVER (PARTITION BY EmployeeID) AS EmployeeTransactionCount
FROM (
    SELECT
        t.EmployeeID,
        e.FullName,
        SUM(t.TotalAmount) AS TotalSales
    FROM Sales.Transactions t
    JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
    GROUP BY t.EmployeeID, e.FullName
) AS grouped
ORDER BY TotalSales DESC
LIMIT 50
