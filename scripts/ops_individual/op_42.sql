-- OP 42: Row-Level Security (RLS) with predicate functions
-- Set session context first
EXEC sp_set_session_context 'UserEmployeeID', 4;

SELECT TOP 50 EmployeeID, FullName, Department, Salary 
FROM HR.Employees;
GO

