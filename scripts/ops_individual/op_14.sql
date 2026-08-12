-- OP 14: OpenJSON with explicit schema for table-valued parsing
SELECT TOP 20 *
FROM OPENJSON((SELECT TOP 1 TransactionDetails FROM Sales.Transactions WHERE TransactionDetails IS NOT NULL))
WITH (
    payment_method NVARCHAR(50) '$.payment_method',
    terms NVARCHAR(20) '$.terms',
    discount_code NVARCHAR(50) '$.discount_code',
    po_number NVARCHAR(50) '$.po_number',
    processed BIT '$.processed'
);
GO

