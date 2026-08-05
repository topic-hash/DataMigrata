-- OP 47 Variant A (Direct translation): MERGE -> INSERT ... ON CONFLICT DO UPDATE.
-- DuckDB supports ON CONFLICT (cols) DO UPDATE for upserts.
-- Assumes Sales.Products(ProductID) has a PRIMARY KEY or UNIQUE constraint.

-- Upsert rows: update existing ProductName/BasePrice, insert new rows.
INSERT INTO Sales.Products (ProductID, ProductName, Category, BasePrice)
VALUES
    (1,    'Quantum Database Server Enterprise v2', 'Software', 54999.99),
    (1001, 'New AI Module 2026',                     'Software', 9999.99)
ON CONFLICT (ProductID) DO UPDATE
SET ProductName = excluded.ProductName,
    BasePrice   = excluded.BasePrice;

-- Note: DuckDB has no native OUTPUT $action. To return action info, query a delta:
-- Use a CTE comparing pre/post states (see Variant B) for the audit-like output.
