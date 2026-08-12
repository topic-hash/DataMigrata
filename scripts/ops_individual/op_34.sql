-- OP 34: Spatial index query optimization
SELECT TOP 50 TransactionID, TotalAmount
FROM Sales.Transactions WITH(INDEX(SIDX_Transactions_Region))
WHERE Region.STDistance(geography::Point(40.7128, -74.0060, 4326)) <= 10000000;
GO

