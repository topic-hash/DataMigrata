-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
-- Translated from T-SQL to DuckDB dialect

SELECT     e.Department,
    e.FullName AS EmployeeName,
    (SELECT 
        t.TransactionID,
        t.TotalAmount,
        t.TransactionDate,
        json_extract_string(t.TransactionDetails::JSON, '$.payment_method') AS PaymentMethod
     FROM Sales.Transactions t
     WHERE t.EmployeeID = e.EmployeeID
     FOR JSON PATH
    ) AS TransactionsJSON
FROM HR.Employees e
WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Sales.Transactions)
FOR JSON PATH, ROOT('SalesReport')
LIMIT 10
