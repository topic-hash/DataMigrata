-- OP 28: View with CROSS APPLY and recursive TVF
-- Translated from T-SQL to DuckDB dialect

SELECT * FROM HR.vw_ManagerHierarchy 
ORDER BY ManagerID, Level
LIMIT 100
