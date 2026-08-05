-- OP 27 Variant C (Pre-computed/materialized): Assumes a view Sales.vw_NormalizedQuarterlySales
-- already exists with (EmployeeID, Quarter, Amount) rows.
SELECT *
FROM Sales.vw_NormalizedQuarterlySales
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter
LIMIT 50;
