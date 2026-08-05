-- OP 9 Variant B: Text parsing approach for XML .exist()
-- Original MSSQL:
--   WHERE EmployeeData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1
--
-- DuckDB translation map:
--   XML .exist('/path[@attr="v"]') = 1
--       -> regexp_matches(EmployeeData, '<Skill\s+level="v"', 'i')
-- XML index -> DuckDB zone maps / regular-expression short-circuit on TEXT column.
--
-- EmployeeData remains an XML string in TEXT (no JSON conversion).

SELECT EmployeeID,
       FullName,
       Department
FROM HR.Employees
WHERE regexp_matches(EmployeeData, '<Skill\s+level="Expert"', 'i')
LIMIT 50;
