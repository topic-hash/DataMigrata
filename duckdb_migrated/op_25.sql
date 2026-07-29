-- OP 25: Inline Table-Valued Function (parameterized view equivalent)
-- Translated from T-SQL to DuckDB dialect

SELECT * FROM Sales.fn_GetEmployeeSales(6, '2026-01-01', '2026-12-31')
ORDER BY TransactionDate
LIMIT 50
