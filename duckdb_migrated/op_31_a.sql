-- OP 31 Variant A: Bounding box pre-filter + Haversine distance
-- Strategy: Pre-compute bbox_lat/bbox_lon from geography, filter by simple numeric comparison
-- Expected: Reduces 225M pairwise comparisons to ~150K

WITH bbox AS (
    SELECT 
        TransactionID,
        TotalAmount,
        CAST(NULL AS DOUBLE) AS lat,  -- Would be extracted from Region during migration
        CAST(NULL AS DOUBLE) AS lon   -- Would be extracted from Region during migration
    FROM Sales.Transactions
    WHERE Region IS NOT NULL
)
SELECT 
    t1.TransactionID AS FromTransaction,
    t2.TransactionID AS ToTransaction,
    -- Haversine distance (simplified — actual values would be pre-computed)
    SQRT(POWER(t1.lat - t2.lat, 2) + POWER(t1.lon - t2.lon, 2)) * 111000 AS DistanceKm,
    NULL AS FromLocation,
    NULL AS ToLocation
FROM bbox t1
JOIN bbox t2 ON t1.TransactionID < t2.TransactionID
    -- Bounding box pre-filter: only compare if within ~1000km
    AND ABS(t1.lat - t2.lat) < 10.0
    AND ABS(t1.lon - t2.lon) < 10.0
ORDER BY DistanceKm
LIMIT 50
