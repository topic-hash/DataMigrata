-- OP 41: Always Encrypted with secure enclaves pattern
-- Translated from T-SQL to DuckDB dialect

OPEN SYMMETRIC KEY EmployeeSymKey
    DECRYPTION BY CERTIFICATE EmployeeDataCert;
SELECT     s.DataID,
    e.FullName,
    CAST(DecryptByKey(s.SSN AS VARCHAR)) AS DecryptedSSN,
    CAST(DecryptByKey(s.CreditCard AS VARCHAR)) AS DecryptedCard,
    CAST(DecryptByKey(s.SalaryEncrypted AS VARCHAR)) AS DecryptedSalary,
    '****-**-' + RIGHT(CAST(DecryptByKey(s.SSN AS VARCHAR)), 4) AS MaskedSSN
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID
LIMIT 50;
CLOSE SYMMETRIC KEY EmployeeSymKey
