-- OP 32: Spatial buffer and intersection calculations
WITH parsed AS (
    SELECT
        TransactionID,
        TotalAmount,
        ST_GeomFromText(Region) AS geom,
        ST_Y(ST_GeomFromText(Region)) AS lat,
        ST_X(ST_GeomFromText(Region)) AS lon
    FROM Sales.Transactions
    WHERE Region IS NOT NULL
)
SELECT
    TransactionID,
    TotalAmount,
    lat AS Latitude,
    lon AS Longitude,
    ST_Distance(geom, ST_Point(-74.0060, 40.7128)) / 1000 AS DistanceFromNYCKm,
    CASE WHEN ST_Distance(geom, ST_Point(-74.0060, 40.7128)) <= 5000000 THEN 'Within Range' ELSE 'Outside Range' END AS Proximity
FROM parsed
ORDER BY TransactionID
LIMIT 50
