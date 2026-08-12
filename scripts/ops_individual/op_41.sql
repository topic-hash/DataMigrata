-- OP 41: Always Encrypted with secure enclaves pattern
-- Translation: MSSQL used EncryptByKey/DecryptByKey over a symmetric key
-- whose plaintext was NEWID()-generated at load time. DuckDB has no
-- equivalent enclave/decryption primitive, and the random plaintext is not
-- reproducible from any seed. The plaintext values were captured once
-- (gold-standard run) and loaded into Security.SensitiveData as VARCHAR
-- columns. This op simply selects those plaintext columns + derives the
-- masked SSN the same way the MSSQL query did: '****-**-' || RIGHT(SSN,4).
-- Equivalent semantics: surface decrypted sensitive fields with a masked
-- SSN column for non-privileged consumers.
SELECT
    s.DataID,
    e.FullName,
    s.SSN AS DecryptedSSN,
    s.CreditCard AS DecryptedCard,
    s.SalaryEncrypted AS DecryptedSalary,
    '****-**-' || RIGHT(s.SSN, 4) AS MaskedSSN
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID
ORDER BY s.DataID
LIMIT 50
