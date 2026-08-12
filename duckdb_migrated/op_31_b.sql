-- OP 31 Variant B: Materialized distance cache
-- Strategy: Pre-compute all pairwise distances during migration; query cache at runtime
-- Expected: O(1) query time, O(n^2) storage (but only for nearby pairs)

SELECT 
    FromTransactionID AS FromTransaction,
    ToTransactionID AS ToTransaction,
    DistanceKm,
    NULL AS FromLocation,
    NULL AS ToLocation
FROM Sales.TransactionDistances  -- Pre-computed during migration
ORDER BY DistanceKm
LIMIT 50
