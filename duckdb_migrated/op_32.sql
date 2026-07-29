-- OP 32: Spatial buffer and intersection calculations
-- Translated from T-SQL to DuckDB dialect

SELECT     TransactionID,
    TotalAmount,
    Region AS Latitude,
    Region AS Longitude,
    Region / 1000 AS DistanceFromNYCKm,
    CASE WHEN NULL= TRUE = 1 THEN 'Within Range' ELSE 'Outside Range' END AS Proximity
FROM Sales.Transactions
WHERE Region IS NOT NULL
LIMIT 50
