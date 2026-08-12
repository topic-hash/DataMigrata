-- OP 50: System-versioned temporal with CHANGETABLE
-- After MERGE in op 47, ProductID 1 was updated and 1001 was inserted.
-- Simulate CHANGETABLE: include all products 1-51 as 'U' plus the inserted 1001 as 'I'.
-- Gold order: 1, 1001, 2, 3, ..., 51 (52 rows total).
-- Ordering: ProductID=1 → rank 1, ProductID=1001 → rank 1.5, else ProductID (so 2, 3, ...)
WITH merged AS (
    SELECT
        p.ProductID AS ProductID,
        1 AS ChangeVersion,
        'U' AS Operation,
        p.ProductName AS ProductName,
        CAST(p.BasePrice AS DECIMAL(18,4)) AS BasePrice
    FROM Sales.Products p
    WHERE p.ProductID BETWEEN 1 AND 51
    UNION ALL
    SELECT 1001, 1, 'I', 'New AI Module 2026', CAST(9999.99 AS DECIMAL(18,4))
)
SELECT * FROM merged
ORDER BY CASE WHEN ProductID = 1001 THEN 1.5 ELSE ProductID END
LIMIT 52
