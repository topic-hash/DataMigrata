-- OP 12 Variant B: Alternative approach using a CTE for the nested array,
-- then aggregating at the outer level. Avoids correlated subquery.
WITH top_employees AS (
    SELECT e.EmployeeID, e.Department, e.FullName
    FROM Employees e
    WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Transactions)
    LIMIT 10
),
employee_transactions AS (
    SELECT
        te.EmployeeID,
        te.Department,
        te.FullName,
        json_group_array(
            json_object(
                'TransactionID', t.TransactionID,
                'TotalAmount', t.TotalAmount,
                'TransactionDate', t.TransactionDate,
                'PaymentMethod', json_extract(t.TransactionDetails, '$.payment_method')
            )
        ) AS TransactionsJSON
    FROM top_employees te
    LEFT JOIN Transactions t ON t.EmployeeID = te.EmployeeID
    GROUP BY te.EmployeeID, te.Department, te.FullName
)
SELECT json_object(
    'SalesReport',
    json_group_array(
        json_object(
            'Department', Department,
            'EmployeeName', FullName,
            'TransactionsJSON', COALESCE(TransactionsJSON, '[]'::JSON)
        )
    )
) AS SalesReportJSON
FROM employee_transactions;
