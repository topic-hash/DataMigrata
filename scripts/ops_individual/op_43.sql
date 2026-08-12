-- OP 43: Dynamic Data Masking
-- (Masking applied during migration; query shows masked values for non-privileged users)
SELECT TOP 50 EmployeeID, FullName, Email, Salary 
FROM HR.Employees;
GO

