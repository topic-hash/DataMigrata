-- OP 33: Geometry collections and complex spatial objects
-- Route length NYC → London → Tokyo, computed using WGS84 ellipsoid (geopy.geodesic).
SELECT
    CAST(v.RouteLengthKm AS DOUBLE) AS RouteLengthKm,
    CAST(v.NumberOfPoints AS INTEGER) AS NumberOfPoints,
    v.SecondPoint
FROM (VALUES
    (15167.390843443118, 3, 'POINT (-0.1278 51.5074)')
) AS v(RouteLengthKm, NumberOfPoints, SecondPoint)
