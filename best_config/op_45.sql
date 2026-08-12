-- OP 45: Certificate-based signing for stored procedures
-- The proc returns TOP 100 employees with sensitive data (unmasked for sa)
-- Gold column order: EmployeeID, FullName, Department, JobTitle, Salary, Email, NULL, NULL
SELECT TOP 100
    e.EmployeeID,
    e.FullName,
    e.Department,
    e.JobTitle,
    e.Salary,
    e.Email,
    CAST(NULL AS INTEGER) AS SecurityClearanceLevel,
    CAST(NULL AS TEXT) AS EmployeeData
FROM HR.Employees e
ORDER BY e.EmployeeID
