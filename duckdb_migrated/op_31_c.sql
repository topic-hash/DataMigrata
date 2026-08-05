-- OP 31 Variant C: Simplified geometry with Haversine formula
-- Strategy: Convert geography to lat/lon DOUBLE columns; compute Haversine in SQL
-- Expected: No spatial extension needed, pure numeric computation

SELECT 
    t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    6371 * 2 * ASIN(SQRT(
        POWER(SIN((t2.lat - t1.lat) * PI() / 180 / 2), 2) +
        COS(t1.lat * PI() / 180) * COS(t2.lat * PI() / 180) *
        POWER(SIN((t2.lon - t1.lon) * PI() / 180 / 2), 2)
    )) AS DistanceKm,
    NULL AS FromLocation,
    NULL AS ToLocation
FROM Sales.Transactions t1
JOIN Sales.Transactions t2 ON t1.TransactionID < t2.TransactionID
WHERE t1.lat IS NOT NULL AND t2.lat IS NOT NULL
    -- Bounding box pre-filter for efficiency
    AND ABS(t1.lat - t2.lat) < 10.0
    AND ABS(t1.lon - t2.lon) < 10.0
ORDER BY DistanceKm
LIMIT 50
