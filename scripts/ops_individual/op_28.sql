-- OP 28: View with CROSS APPLY and recursive TVF
SELECT TOP 100 * FROM HR.vw_ManagerHierarchy 
ORDER BY ManagerID, Level;
GO

