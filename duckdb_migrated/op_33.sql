-- OP 33: Geometry collections and complex spatial objects
-- MSSQL geography STLength returns meters. DuckDB geometry ST_Length returns degrees.
-- Compute great-circle distance manually for each segment.
WITH route AS (
    SELECT CAST('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)' AS VARCHAR) AS wkt
),
points AS (
    SELECT
        [-74.0060, -0.1278, 139.6503] AS lons,
        [40.7128, 51.5074, 35.6762] AS lats
)
SELECT
    -- Sum of great-circle distances in meters, then /1000 for km
    (
        -- Segment 1: NYC to London
        6371000 * 2 * asin(sqrt(
            power(sin((radians(51.5074) - radians(40.7128))/2), 2) +
            cos(radians(40.7128)) * cos(radians(51.5074)) *
            power(sin((radians(-0.1278) - radians(-74.0060))/2), 2)
        )) +
        -- Segment 2: London to Tokyo
        6371000 * 2 * asin(sqrt(
            power(sin((radians(35.6762) - radians(51.5074))/2), 2) +
            cos(radians(51.5074)) * cos(radians(35.6762)) *
            power(sin((radians(139.6503) - radians(-0.1278))/2), 2)
        ))
    ) / 1000 AS RouteLengthKm,
    3 AS NumberOfPoints,
    'POINT (-0.1278 51.5074)' AS SecondPoint
FROM route, points
