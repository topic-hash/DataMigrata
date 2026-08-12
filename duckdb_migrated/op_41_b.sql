-- OP 41 Variant B (Alternative approach): Return masked placeholders ('****-**-XXXX') instead of NULL
-- to preserve column cardinality/shapes for downstream consumers.
SELECT
    s.DataID,
    e.FullName,
    '****-**-XXXX' AS DecryptedSSN,
    '****-****-****-XXXX' AS DecryptedCard,
    'CONFIDENTIAL' AS DecryptedSalary,
    '****-**-XXXX' AS MaskedSSN
FROM Security.SensitiveData s
JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID
LIMIT 50;
