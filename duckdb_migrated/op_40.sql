-- OP 40: Batch mode on rowstore
-- Translated from T-SQL to DuckDB dialect

SELECT     t.EmployeeID,
    e.FullName,
    SUM(t.TotalAmount) AS TotalSales,
    COUNT(*) OVER (PARTITION BY t.EmployeeID) AS EmployeeTransactionCount
FROM Sales.Transactions t
JOIN HR.Employees e ON t.EmployeeID = e.EmployeeID
GROUP BY t.EmployeeID, e.FullName
ORDER BY TotalSales DESC
)
LIMIT 50;
-- ============================================================================
-- CATEGORY 8: SECURITY & ENCRYPTION (Operations 41-45)
-- ============================================================================
