-- OP 33: Geometry collections and complex spatial objects
DECLARE @route GEOGRAPHY = geography::STGeomFromText(
    'LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)', 4326);

SELECT 
    @route.STLength() / 1000 AS RouteLengthKm,
    @route.STNumPoints() AS NumberOfPoints,
    @route.STPointN(2).STAsText() AS SecondPoint;
GO

