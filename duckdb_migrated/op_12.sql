-- OP 12: JSON aggregation with FOR JSON (hierarchical nested JSON)
WITH EmployeeTransactions AS (
    SELECT
        e.Department,
        e.EmployeeID,
        e.FullName AS EmployeeName,
        (
            SELECT '[' || string_agg(
                '{"TransactionID":' || CAST(t.TransactionID AS VARCHAR) ||
                ',"TotalAmount":' || CAST(t.TotalAmount AS VARCHAR) ||
                ',"TransactionDate":"' || CAST(t.TransactionDate AS VARCHAR) || '"' ||
                ',"PaymentMethod":"' || json_extract_string(t.TransactionDetails, '$.payment_method') || '"}',
                ','
            ) || ']'
            FROM Sales.Transactions t
            WHERE t.EmployeeID = e.EmployeeID
        ) AS TransactionsJSON
    FROM HR.Employees e
    WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Sales.Transactions)
    ORDER BY e.Department, e.EmployeeID
    LIMIT 10
)
SELECT
    '[{"Department":"' || Department || '","EmployeeName":"' || EmployeeName || '","TransactionsJSON":' || TransactionsJSON || '}]' AS SalesReport
FROM EmployeeTransactions
