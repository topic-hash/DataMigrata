-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
-- Force truncation (not rounding) for AvgSales to match MSSQL behavior
SELECT
    Department,
    Employee,
    GroupingLevel,
    TransactionCount,
    CAST(TotalSales AS DECIMAL(36,8)) AS TotalSales,
    CAST(trunc(AvgSales, 8) AS DECIMAL(36,8)) AS AvgSales
FROM Sales.vw_MultiDimensionalSales
ORDER BY GroupingLevel, Department, Employee
LIMIT 100
