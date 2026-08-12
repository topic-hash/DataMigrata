-- OP 17: Temporal querying - BETWEEN
SELECT TOP 50
    TransactionID, TotalAmount, ValidFrom, ValidTo,
    CASE 
        WHEN ValidTo = '9999-12-31 23:59:59.9999999' THEN 'Current'
        ELSE 'Historical'
    END AS RecordState
FROM Sales.Transactions
FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-12-31'
ORDER BY TransactionID, ValidFrom;
GO

