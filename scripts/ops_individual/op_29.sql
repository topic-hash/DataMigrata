-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
SELECT TOP 100 * FROM Sales.vw_MultiDimensionalSales 
ORDER BY GroupingLevel, Department, Employee;
GO

