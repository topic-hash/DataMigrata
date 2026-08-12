-- OP 29: View with GROUPING SETS for multi-dimensional aggregation
-- Recompute AvgSales using floor(mul*1e8/count)/1e8 to TRUNCATE (not round) to 8 places
SELECT
    Department,
    Employee,
    GroupingLevel,
    TransactionCount,
    CAST(TotalSales AS DECIMAL(36,8)) AS TotalSales,
    CASE WHEN TransactionCount > 0
         THEN CAST(CAST(CAST(floor(CAST(TotalSales AS DECIMAL(38,8)) * 100000000 / TransactionCount) AS BIGINT) AS DECIMAL(36,8)) / CAST(100000000 AS DECIMAL(36,8)) AS DECIMAL(36,8))
         ELSE NULL
    END AS AvgSales
FROM Sales.vw_MultiDimensionalSales
ORDER BY GroupingLevel, Department, Employee
LIMIT 100
