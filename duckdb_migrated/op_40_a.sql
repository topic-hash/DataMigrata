-- OP 40 Variant A (Direct translation): Remove OPTION (USE HINT('ALLOW_BATCH_MODE')) hint.
-- DuckDB does not support batch-mode hints (and does not need them); drop the clause.
SELECT
    t.EmployeeID,
    e.FullName,
    SUM(t.TotalAmount) AS TotalSales,
    COUNT(*) OVER (PARTITION BY t.EmployeeID) AS EmployeeTransactionCount
FROM Sales.Transactions t
JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
GROUP BY t.EmployeeID, e.FullName
ORDER BY TotalSales DESC
LIMIT 50;
