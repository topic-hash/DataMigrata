-- OP 14: OpenJSON with explicit schema for table-valued parsing
-- Translated from T-SQL to DuckDB dialect

SELECT *
FROM OPENJSON((SELECT TOP 1 TransactionDetails FROM Sales.Transactions WHERE TransactionDetails IS NOT NULL))
WITH (
    payment_method VARCHAR(50) '$.payment_method',
    terms VARCHAR(20) '$.terms',
    discount_code VARCHAR(50) '$.discount_code',
    po_number VARCHAR(50) '$.po_number',
    processed BIT '$.processed'
)
LIMIT 20
