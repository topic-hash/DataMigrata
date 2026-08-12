-- OP 45: Certificate-based signing for stored procedures
-- The proc returns TOP 100 employees with their sensitive data (unmasked for sa)
SELECT TOP 100
    e.EmployeeID,
    e.FullName,
    e.Email,
    e.Department,
    e.JobTitle,
    e.Salary,
    e.HireDate,
    e.SecurityClearanceLevel
FROM HR.Employees e
ORDER BY e.EmployeeID
