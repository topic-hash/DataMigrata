-- OP 40 Variant C (Pre-computed/materialized): Assumes Sales.vw_EmployeeSalesSummary
-- already aggregates (EmployeeID, FullName, TotalSales, TransactionCount).
SELECT
    EmployeeID,
    FullName,
    TotalSales,
    TransactionCount AS EmployeeTransactionCount
FROM Sales.vw_EmployeeSalesSummary
ORDER BY TotalSales DESC
LIMIT 50;
