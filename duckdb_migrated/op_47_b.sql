-- OP 47 Variant B (Alternative approach): Split into separate UPDATE and INSERT to capture $action.
-- Capture old values first, then perform UPDATE on matched rows and INSERT on non-matched rows.
CREATE OR REPLACE TEMP TABLE merge_source AS
SELECT * FROM (VALUES
    (1,    'Quantum Database Server Enterprise v2', 'Software', 54999.99),
    (1001, 'New AI Module 2026',                     'Software', 9999.99)
) AS t(ProductID, ProductName, Category, BasePrice);

CREATE OR REPLACE TEMP TABLE merge_audit AS
SELECT 'UPDATE' AS ActionTaken, s.ProductID,
       s.ProductName AS NewName, p.ProductName AS OldName,
       s.BasePrice   AS NewPrice, p.BasePrice   AS OldPrice
FROM merge_source s
JOIN Sales.Products p ON p.ProductID = s.ProductID;

-- Apply UPDATE for matched rows.
UPDATE Sales.Products
SET ProductName = s.ProductName,
    BasePrice   = s.BasePrice
FROM merge_source s
WHERE Sales.Products.ProductID = s.ProductID;

-- Apply INSERT for unmatched rows, recording action.
INSERT INTO merge_audit
SELECT 'INSERT', s.ProductID, s.ProductName, CAST(NULL AS VARCHAR), s.BasePrice, CAST(NULL AS DECIMAL(18,2))
FROM merge_source s
LEFT JOIN Sales.Products p ON p.ProductID = s.ProductID
WHERE p.ProductID IS NULL;

INSERT INTO Sales.Products (ProductID, ProductName, Category, BasePrice)
SELECT s.ProductID, s.ProductName, s.Category, s.BasePrice
FROM merge_source s
LEFT JOIN Sales.Products p ON p.ProductID = s.ProductID
WHERE p.ProductID IS NULL;

-- Mimic OUTPUT $action / INSERTED.* / DELETED.*.
SELECT ActionTaken, ProductID, NewName, OldName, NewPrice, OldPrice
FROM merge_audit;
