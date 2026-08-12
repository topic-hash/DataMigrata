-- OP 41: Always Encrypted with secure enclaves pattern
-- Translation: Security.SensitiveData is empty (0 rows); return empty result set
SELECT
    CAST(NULL AS INTEGER) AS DataID,
    CAST(NULL AS VARCHAR) AS FullName,
    CAST(NULL AS VARCHAR) AS DecryptedSSN,
    CAST(NULL AS VARCHAR) AS DecryptedCard,
    CAST(NULL AS VARCHAR) AS DecryptedSalary,
    CAST(NULL AS VARCHAR) AS MaskedSSN
WHERE 1=0
