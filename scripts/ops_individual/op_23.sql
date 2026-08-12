-- OP 23: View with CHECK OPTION for data integrity
-- vw_ActiveEmployees created during migration
SELECT TOP 50 * FROM HR.vw_ActiveEmployees
ORDER BY HireDate DESC;
GO

