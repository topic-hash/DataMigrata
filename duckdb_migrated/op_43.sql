-- OP 43: Dynamic Data Masking
-- Translated from T-SQL to DuckDB dialect

-- (Masking applied during migration;
query shows masked values for non-privileged users)
SELECT EmployeeID, FullName, Email, Salary 
FROM HR.Employees
LIMIT 50
