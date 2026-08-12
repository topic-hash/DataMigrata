-- OP 38: Memory-optimized table with hash index
SELECT * FROM Sales.HighSpeedLookup
WHERE LookupKey BETWEEN 100 AND 200
ORDER BY LookupKey
LIMIT 50
