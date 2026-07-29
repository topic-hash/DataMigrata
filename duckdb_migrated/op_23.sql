-- OP 23: View with CHECK OPTION for data integrity
-- Translated from T-SQL to DuckDB dialect

-- vw_ActiveEmployees created during migration
SELECT * FROM HR.vw_ActiveEmployees
ORDER BY HireDate DESC
LIMIT 50
