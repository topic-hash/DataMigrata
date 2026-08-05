-- OP 41 Variant C (Pre-computed/materialized): Assumes a view Security.vw_SensitiveDataMasked
-- already exists and returns NULL/placeholder values for the encrypted columns.
-- Schema (assumed):
--   CREATE VIEW Security.vw_SensitiveDataMasked AS
--   SELECT s.DataID, e.FullName,
--          NULL AS DecryptedSSN, NULL AS DecryptedCard, NULL AS DecryptedSalary,
--          NULL AS MaskedSSN
--   FROM Security.SensitiveData s
--   JOIN HR.Employees e ON s.EmployeeID = e.EmployeeID;

SELECT DataID, FullName, DecryptedSSN, DecryptedCard, DecryptedSalary, MaskedSSN
FROM Security.vw_SensitiveDataMasked
LIMIT 50;
