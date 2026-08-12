-- OP 42: Row-Level Security (RLS) with predicate functions
-- Translated from T-SQL to DuckDB dialect

-- Set session context first

SELECT EmployeeID, FullName, Department, Salary 
FROM HR.Employees
LIMIT 50
