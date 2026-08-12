-- OP 34: Spatial index query optimization
SELECT TransactionID, TotalAmount
FROM Sales.Transactions
WHERE Region IS NOT NULL
  AND ST_Distance(ST_GeomFromText(Region), ST_Point(-74.0060, 40.7128)) <= 10000000
ORDER BY TransactionID
LIMIT 50
