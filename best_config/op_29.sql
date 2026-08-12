-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
-- Translated from T-SQL to DuckDB dialect

SELECT * FROM Sales.vw_MultiDimensionalSales 
ORDER BY GroupingLevel, Department, Employee
LIMIT 100
