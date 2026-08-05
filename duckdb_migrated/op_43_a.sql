-- OP 43 Variant A (Direct translation): DDM -> CASE WHEN to mask values.
-- Reproduce MSSQL Dynamic Data Masking behavior in DuckDB using CASE expressions.
SELECT
    EmployeeID,
    FullName,
    CASE
        WHEN Email IS NULL THEN NULL
        ELSE LEFT(Email, 1) || 'XXX' || SUBSTR(Email, POSITION('@' IN Email))
    END AS Email,
    CASE
        WHEN Salary IS NULL THEN NULL
        ELSE 0.00
    END AS Salary
FROM HR.Employees
LIMIT 50;
