ALTER TABLE HR.Employees NOCHECK CONSTRAINT ALL;
GO

INSERT INTO HR.Employees (ManagerID, FullName, Email, Department, JobTitle, Salary, HireDate, SecurityClearanceLevel)
SELECT TOP 5000
    NULL,
    'Employee_' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR(10)),
    'employee' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS VARCHAR(10)) + '@dataMigrata.com',
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
        WHEN 0 THEN 'Engineering' WHEN 1 THEN 'Sales' WHEN 2 THEN 'Marketing'
        WHEN 3 THEN 'HR' WHEN 4 THEN 'Finance' WHEN 5 THEN 'Operations'
        WHEN 6 THEN 'Legal' WHEN 7 THEN 'R&D' WHEN 8 THEN 'Customer Success'
        ELSE 'IT' END,
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 10)
        WHEN 0 THEN 'Senior Engineer' WHEN 1 THEN 'Account Executive' WHEN 2 THEN 'Marketing Manager'
        WHEN 3 THEN 'HR Specialist' WHEN 4 THEN 'Financial Analyst' WHEN 5 THEN 'Operations Director'
        WHEN 6 THEN 'Legal Counsel' WHEN 7 THEN 'Research Scientist' WHEN 8 THEN 'Customer Success Manager'
        ELSE 'IT Architect' END,
    55000 + (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 150) * 1000,
    DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 3650), CAST('2026-07-22' AS DATE)),
    (ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 5) + 1
FROM master..spt_values a CROSS JOIN master..spt_values b
WHERE a.type = 'P' AND b.type = 'P';
GO

UPDATE HR.Employees
SET ManagerID = CASE WHEN EmployeeID <= 100 THEN NULL ELSE (EmployeeID % 100) + 1 END;
GO

ALTER TABLE HR.Employees WITH CHECK CHECK CONSTRAINT ALL;
GO

SELECT COUNT(*) AS EmployeeCount FROM HR.Employees;
GO
