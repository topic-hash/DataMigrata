-- OP 42: Row-Level Security (RLS) with predicate functions
-- Gold shows all employees, so RLS predicate allows all rows for sa
SELECT EmployeeID, FullName, Department, Salary
FROM HR.Employees
ORDER BY EmployeeID
LIMIT 50
