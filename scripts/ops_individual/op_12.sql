-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
SELECT TOP 10
    e.Department,
    e.FullName AS EmployeeName,
    (SELECT 
        t.TransactionID,
        t.TotalAmount,
        t.TransactionDate,
        JSON_VALUE(t.TransactionDetails, '$.payment_method') AS PaymentMethod
     FROM Sales.Transactions t
     WHERE t.EmployeeID = e.EmployeeID
     FOR JSON PATH
    ) AS TransactionsJSON
FROM HR.Employees e
WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Sales.Transactions)
FOR JSON PATH, ROOT('SalesReport');
GO

