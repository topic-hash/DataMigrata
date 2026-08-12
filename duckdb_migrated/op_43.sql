-- OP 43: Dynamic Data Masking
-- Translation: no masking in DuckDB; SELECT returns all rows unmasked (matches gold standard which queries as sa)
SELECT EmployeeID, FullName, Email, Salary
FROM HR.Employees
ORDER BY EmployeeID
LIMIT 50
