-- OP 41: Always Encrypted with secure enclaves pattern
OPEN SYMMETRIC KEY EmployeeSymKey
    DECRYPTION BY CERTIFICATE EmployeeDataCert;

SELECT TOP 50
    s.DataID,
    e.FullName,
    CONVERT(VARCHAR, DecryptByKey(s.SSN)) AS DecryptedSSN,
    CONVERT(VARCHAR, DecryptByKey(s.CreditCard)) AS DecryptedCard,
    CONVERT(VARCHAR, DecryptByKey(s.SalaryEncrypted)) AS DecryptedSalary,
    '****-**-' + RIGHT(CONVERT(VARCHAR, DecryptByKey(s.SSN)), 4) AS MaskedSSN
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID;

CLOSE SYMMETRIC KEY EmployeeSymKey;
GO

