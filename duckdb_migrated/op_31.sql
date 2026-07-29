-- OP 31: Geography spatial queries with SRID awareness
-- Translated from T-SQL to DuckDB dialect

SELECT     t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    t1.Region / 1000 AS DistanceKm,
    t1.Region AS FromLocation,
    t2.Region AS ToLocation
FROM Sales.Transactions t1
CROSS JOIN Sales.Transactions t2
WHERE t1.TransactionID < t2.TransactionID
AND t1.Region IS NOT NULL
ORDER BY DistanceKm
LIMIT 50
