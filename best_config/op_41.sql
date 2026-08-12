-- OP 41 Variant A (Direct translation): Always Encrypted -> return NULL for encrypted columns.
-- DuckDB has no symmetric-key/certificate decryption; expose NULL (or empty) for SSN/CreditCard/Salary.
SELECT
    s.DataID,
    e.FullName,
    CAST(NULL AS VARCHAR) AS DecryptedSSN,
    CAST(NULL AS VARCHAR) AS DecryptedCard,
    CAST(NULL AS VARCHAR) AS DecryptedSalary,
    CAST(NULL AS VARCHAR) AS MaskedSSN
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID
LIMIT 50;
