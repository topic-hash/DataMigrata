-- OP 47: MERGE statement with OUTPUT clause and $action
-- Translated from T-SQL to DuckDB dialect

MERGE Sales.Products AS target
USING (VALUES 
    (1, 'Quantum Database Server Enterprise v2', 'Software', 54999.99),
    (1001, 'New AI Module 2026', 'Software', 9999.99)
) AS source (ProductID, ProductName, Category, BasePrice)
ON target.ProductID = source.ProductID
WHEN MATCHED THEN
    UPDATE SET ProductName = source.ProductName, BasePrice = source.BasePrice
WHEN NOT MATCHED THEN
    INSERT (ProductName, Category, BasePrice) 
    VALUES (source.ProductName, source.Category, source.BasePrice)
OUTPUT 
    'UPDATE' AS ActionTaken,
    INSERTED.ProductID,
    INSERTED.ProductName AS NewName,
    DELETED.ProductName AS OldName,
    INSERTED.BasePrice AS NewPrice,
    DELETED.BasePrice AS OldPrice
