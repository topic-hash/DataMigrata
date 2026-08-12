-- OP 23: View with CHECK OPTION for data integrity
SELECT * FROM HR.vw_ActiveEmployees
ORDER BY HireDate DESC, EmployeeID ASC
LIMIT 50
