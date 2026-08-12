-- OP 28: View with CROSS APPLY and recursive TVF
SELECT ManagerID, EmployeeID, FullName, Level
FROM HR.vw_ManagerHierarchy
ORDER BY ManagerID NULLS FIRST, Level, EmployeeID
LIMIT 100
