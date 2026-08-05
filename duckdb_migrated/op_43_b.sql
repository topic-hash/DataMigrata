-- OP 43 Variant B (Alternative approach): Use regexp_replace for Email masking and a fixed mask for Salary.
SELECT
    EmployeeID,
    FullName,
    regexp_replace(COALESCE(Email, ''), '^([^@]).*(@.*)$', '\1XXX\2') AS Email,
    CASE WHEN Salary IS NULL THEN NULL ELSE 0.00 END AS Salary
FROM HR.Employees
LIMIT 50;
