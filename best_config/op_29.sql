-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
SELECT
    Department,
    Employee,
    GroupingLevel,
    TransactionCount,
    CAST(TotalSales AS DECIMAL(36,8)) AS TotalSales,
    CAST(AvgSales AS DECIMAL(36,8)) AS AvgSales
FROM Sales.vw_MultiDimensionalSales
ORDER BY GroupingLevel, Department, Employee
LIMIT 100
