-- OP 26: View with PIVOT for cross-tabulation
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    CAST(Q1 AS DECIMAL(36,8)) AS Q1,
    CAST(Q2 AS DECIMAL(36,8)) AS Q2,
    CAST(Q3 AS DECIMAL(36,8)) AS Q3,
    CAST(Q4 AS DECIMAL(36,8)) AS Q4
FROM Sales.vw_EmployeeQuarterlySales
ORDER BY EmployeeID
