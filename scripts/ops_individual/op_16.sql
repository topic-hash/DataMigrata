-- OP 16: Temporal querying - AS OF
DECLARE @AsOfDate DATETIME2 = DATEADD(DAY, -1, SYSUTCDATETIME());

SELECT TOP 50
    TransactionID, EmployeeID, TotalAmount, TransactionDate,
    ValidFrom, ValidTo
FROM Sales.Transactions FOR SYSTEM_TIME AS OF @AsOfDate
ORDER BY TransactionID;
GO

