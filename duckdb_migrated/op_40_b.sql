-- OP 40 Variant B (Alternative approach): Pre-aggregate in a CTE, then attach windowed count.
WITH sales AS (
    SELECT
        t.EmployeeID,
        e.FullName,
        SUM(t.TotalAmount) AS TotalSales,
        COUNT(*)            AS TxCount
    FROM Sales.Transactions t
    JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
    GROUP BY t.EmployeeID, e.FullName
)
SELECT
    EmployeeID,
    FullName,
    TotalSales,
    TxCount AS EmployeeTransactionCount
FROM sales
ORDER BY TotalSales DESC
LIMIT 50;
