-- OP 27: View with UNPIVOT for normalization
SELECT
    EmployeeID,
    FullName,
    SaleYear,
    Quarter,
    CAST(Amount AS DECIMAL(36,8)) AS Amount
FROM Sales.vw_NormalizedQuarterlySales
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter
LIMIT 50
