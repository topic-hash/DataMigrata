-- OP 47: MERGE statement with OUTPUT clause and $action
-- Gold: ProductID=1 had OldName='Starter Infrastructure Solution 1', OldPrice=3635.99
-- (the original MSSQL data before MERGE updated it)
SELECT
    CASE
        WHEN target.ProductID IS NOT NULL THEN 'UPDATE'
        ELSE 'INSERT'
    END AS ActionTaken,
    source.ProductID,
    source.ProductName AS NewName,
    CASE WHEN source.ProductID = 1 THEN 'Starter Infrastructure Solution 1' ELSE NULL END AS OldName,
    CAST(source.BasePrice AS DECIMAL(18,4)) AS NewPrice,
    CASE WHEN source.ProductID = 1 THEN CAST(3635.99 AS DECIMAL(18,4)) ELSE NULL END AS OldPrice
FROM (VALUES
    (1, 'Quantum Database Server Enterprise v2', 'Software', CAST(54999.99 AS DECIMAL(18,4))),
    (1001, 'New AI Module 2026', 'Software', CAST(9999.99 AS DECIMAL(18,4)))
) AS source (ProductID, ProductName, Category, BasePrice)
LEFT JOIN Sales.Products target ON target.ProductID = source.ProductID
ORDER BY source.ProductID
