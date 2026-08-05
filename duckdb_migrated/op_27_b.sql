-- OP 27 Variant B (Alternative approach): Use UNPIVOT emulation via a list of structs + unnest.
SELECT
    EmployeeID,
    q.Quarter,
    q.Amount
FROM Sales.vw_EmployeeQuarterlySales,
LATERAL (
    SELECT * FROM (VALUES
        ('Q1', Q1),
        ('Q2', Q2),
        ('Q3', Q3),
        ('Q4', Q4)
    ) AS t(Quarter, Amount)
    WHERE t.Amount IS NOT NULL
) AS q
ORDER BY EmployeeID, q.Quarter
LIMIT 50;
