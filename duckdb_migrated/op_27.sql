-- OP 27: View with UNPIVOT for normalization
-- Translated from T-SQL to DuckDB dialect

SELECT * FROM Sales.vw_NormalizedQuarterlySales 
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter
LIMIT 50
