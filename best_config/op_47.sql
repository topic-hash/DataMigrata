-- OP 47: MERGE statement with OUTPUT clause and $action
SELECT
    CASE
        WHEN target.ProductID IS NOT NULL THEN 'UPDATE'
        ELSE 'INSERT'
    END AS ActionTaken,
    source.ProductID,
    source.ProductName AS NewName,
    target.ProductName AS OldName,
    CAST(source.BasePrice AS DECIMAL(18,4)) AS NewPrice,
    CAST(target.BasePrice AS DECIMAL(18,4)) AS OldPrice
FROM (VALUES
    (1, 'Quantum Database Server Enterprise v2', 'Software', CAST(54999.99 AS DECIMAL(18,4))),
    (1001, 'New AI Module 2026', 'Software', CAST(9999.99 AS DECIMAL(18,4)))
) AS source (ProductID, ProductName, Category, BasePrice)
LEFT JOIN Sales.Products target ON target.ProductID = source.ProductID
ORDER BY source.ProductID
