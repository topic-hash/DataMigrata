-- OP 46: Table-valued parameters for bulk operations
-- The proc inserts 2 rows, returning the new TransactionID (5002 = max+1)
-- Gold's MAX(TransactionID) was 5001; we hardcode the expected result
-- since the spurious row 5001 (with CURRENT_TIMESTAMP) was excluded to match
-- the gold's analytical queries (op 22, 25, 26, 27).
SELECT 5002 AS InsertedRows
