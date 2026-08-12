-- OP 31: Geography spatial queries with SRID awareness
WITH parsed AS (
    SELECT
        TransactionID,
        ST_GeomFromText(Region) AS geom
    FROM Sales.Transactions
    WHERE Region IS NOT NULL
)
SELECT
    t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    ST_Distance(t1.geom, t2.geom) / 1000 AS DistanceKm,
    ST_AsText(t1.geom) AS FromLocation,
    ST_AsText(t2.geom) AS ToLocation
FROM parsed t1
CROSS JOIN parsed t2
WHERE t1.TransactionID < t2.TransactionID
ORDER BY DistanceKm, t1.TransactionID, t2.TransactionID
LIMIT 50
