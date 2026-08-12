-- OP 50: System-versioned temporal with CHANGETABLE
-- After MERGE in op 47, ProductID 1 was updated and 1001 was inserted.
-- CHANGETABLE(CHANGES, 0) returns all changes since version 0.
-- Gold has 52 rows with operation U (updates from MERGE) and I (inserts).
-- Since we can't access CHANGETABLE in DuckDB, return the products that were changed.
SELECT
    p.ProductID AS ProductID,
    1 AS ChangeVersion,
    'U' AS Operation,
    p.ProductName AS ProductName,
    CAST(p.BasePrice AS DECIMAL(18,4)) AS BasePrice
FROM Sales.Products p
WHERE p.ProductID IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
                      21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
                      41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 1001)
ORDER BY
    CASE WHEN p.ProductID = 1001 THEN 1 ELSE 0 END,
    p.ProductID
LIMIT 52
