-- OP 32: Spatial buffer and intersection calculations
DECLARE @nyc GEOGRAPHY = geography::Point(40.7128, -74.0060, 4326);
DECLARE @bufferRadius INT = 5000000;

SELECT TOP 50
    TransactionID,
    TotalAmount,
    Region.Lat AS Latitude,
    Region.Long AS Longitude,
    Region.STDistance(@nyc) / 1000 AS DistanceFromNYCKm,
    CASE WHEN @nyc.STBuffer(@bufferRadius).STIntersects(Region) = 1 THEN 'Within Range' ELSE 'Outside Range' END AS Proximity
FROM Sales.Transactions
WHERE Region IS NOT NULL;
GO

