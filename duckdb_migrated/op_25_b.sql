-- OP 25 Variant B (Alternative approach): Use a parameterized view (macro-style) via a DuckDB view
-- filtered at query time. The view returns all employees and rows; filter is applied externally.
-- View definition (assumed pre-created):
--   CREATE VIEW Sales.vw_EmployeeSales AS
--   SELECT t.TransactionID, t.EmployeeID, e.FullName, t.TotalAmount, t.TransactionDate
--   FROM Sales.Transactions t JOIN HR.Employees e ON e.EmployeeID = t.EmployeeID;

SELECT *
FROM Sales.vw_EmployeeSales
WHERE EmployeeID = 6
  AND TransactionDate BETWEEN TIMESTAMP '2026-01-01' AND TIMESTAMP '2026-12-31'
ORDER BY TransactionDate
LIMIT 50;
