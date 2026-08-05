-- OP 27 Variant A (Direct translation): UNPIVOT -> UNION ALL of per-column selects.
-- The MSSQL view vw_NormalizedQuarterlySales pivots Q1..Q4 columns into rows.
-- Reconstruct directly from underlying Sales.vw_EmployeeQuarterlySales (Q1, Q2, Q3, Q4 columns).
WITH unpivoted AS (
    SELECT EmployeeID, 'Q1' AS Quarter, Q1 AS Amount FROM Sales.vw_EmployeeQuarterlySales WHERE Q1 IS NOT NULL
    UNION ALL
    SELECT EmployeeID, 'Q2' AS Quarter, Q2 AS Amount FROM Sales.vw_EmployeeQuarterlySales WHERE Q2 IS NOT NULL
    UNION ALL
    SELECT EmployeeID, 'Q3' AS Quarter, Q3 AS Amount FROM Sales.vw_EmployeeQuarterlySales WHERE Q3 IS NOT NULL
    UNION ALL
    SELECT EmployeeID, 'Q4' AS Quarter, Q4 AS Amount FROM Sales.vw_EmployeeQuarterlySales WHERE Q4 IS NOT NULL
)
SELECT *
FROM unpivoted
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter
LIMIT 50;
