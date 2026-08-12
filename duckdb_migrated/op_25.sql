-- OP 25: Inline Table-Valued Function (parameterized view equivalent)
SELECT * FROM Sales.fn_GetEmployeeSales(6, '2026-01-01'::DATE, '2026-12-31'::DATE)
ORDER BY TransactionDate
LIMIT 50
