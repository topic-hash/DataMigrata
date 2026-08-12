-- OP 35: Multi-polygon territory analysis
DECLARE @salesTerritory GEOGRAPHY = geography::STGeomFromText(
    'MULTIPOLYGON(((-125 25, -100 25, -100 50, -125 50, -125 25)), 
                  ((-100 30, -80 30, -80 45, -100 45, -100 30)))', 4326).MakeValid();

SELECT TOP 50
    t.TransactionID,
    t.TotalAmount,
    @salesTerritory.STContains(t.Region) AS IsInTerritory
FROM Sales.Transactions t
WHERE t.Region IS NOT NULL;
GO

-- ============================================================================
-- CATEGORY 7: COLUMNSTORE & IN-MEMORY (Operations 36-40)
-- ============================================================================

