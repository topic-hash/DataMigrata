-- OP 35: Multi-polygon territory analysis
-- Translation: build multipolygon, check ST_Contains
SELECT
    t.TransactionID,
    t.TotalAmount,
    CASE WHEN ST_Contains(
        ST_GeomFromText('MULTIPOLYGON(((-125 25, -100 25, -100 50, -125 50, -125 25)), ((-100 30, -80 30, -80 45, -100 45, -100 30)))'),
        ST_GeomFromText(t.Region)
    ) THEN 1 ELSE 0 END AS IsInTerritory
FROM Sales.Transactions t
WHERE t.Region IS NOT NULL
ORDER BY t.TransactionID
LIMIT 50
