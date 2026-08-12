-- OP 43 Variant C (Pre-computed/materialized): Assumes a view HR.vw_EmployeesMasked
-- already applies the masking rules at view level.
-- Schema (assumed):
--   CREATE VIEW HR.vw_EmployeesMasked AS
--   SELECT EmployeeID, FullName,
--          regexp_replace(Email, '^([^@]).*(@.*)$', '\1XXX\2') AS Email,
--          0.00 AS Salary
--   FROM HR.Employees;

SELECT EmployeeID, FullName, Email, Salary
FROM HR.vw_EmployeesMasked
LIMIT 50;
