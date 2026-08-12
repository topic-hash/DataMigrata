-- OP 25 Variant C (Pre-computed/materialized): Assumes a pre-materialized table
-- Sales.EmployeeSales_ByDate(EmployeeID, StartDate, EndDate, TransactionID, FullName, TotalAmount, TransactionDate)
-- populated for known parameter combinations.
SELECT
    TransactionID, EmployeeID, FullName, TotalAmount, TransactionDate
FROM Sales.EmployeeSales_ByDate
WHERE EmployeeID = 6
  AND StartDate  = TIMESTAMP '2026-01-01'
  AND EndDate    = TIMESTAMP '2026-12-31'
ORDER BY TransactionDate
LIMIT 50;
