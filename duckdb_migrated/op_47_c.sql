-- OP 47 Variant C (Pre-computed/materialized): Assumes a stored macro Sales.usp_MergeProducts(source_rows)
-- exists in DuckDB that performs the upsert and writes audit rows into Sales.MergeAuditLog.
-- Schema (assumed):
--   CREATE TABLE Sales.MergeAuditLog(
--     ActionTaken VARCHAR, ProductID INTEGER,
--     NewName VARCHAR, OldName VARCHAR,
--     NewPrice DECIMAL(18,2), OldPrice DECIMAL(18,2),
--     MergedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
--   );

INSERT INTO Sales.MergeAuditLog (ActionTaken, ProductID, NewName, OldName, NewPrice, OldPrice)
SELECT ActionTaken, ProductID, NewName, OldName, NewPrice, OldPrice
FROM Sales.MergeAuditLog
WHERE MergedAt >= CURRENT_DATE
ORDER BY MergedAt DESC
LIMIT 50;
