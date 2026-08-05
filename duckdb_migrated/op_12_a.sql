-- OP 12 Variant A: Direct translation (FOR JSON PATH → json_group_array / json_object)
-- DuckDB equivalent of hierarchical nested JSON aggregation.
-- Note: DuckDB has no schema "Sales." by default; tables assumed in main schema.
SELECT json_object(
    'SalesReport',
    json_group_array(
        json_object(
            'Department', e.Department,
            'EmployeeName', e.FullName,
            'TransactionsJSON', COALESCE((
                SELECT json_group_array(
                    json_object(
                        'TransactionID', t.TransactionID,
                        'TotalAmount', t.TotalAmount,
                        'TransactionDate', t.TransactionDate,
                        'PaymentMethod', json_extract(t.TransactionDetails, '$.payment_method')
                    )
                )
                FROM Transactions t
                WHERE t.EmployeeID = e.EmployeeID
            ), '[]'::JSON)
        )
    )
) AS SalesReportJSON
FROM (
    SELECT DISTINCT e.Department, e.FullName, e.EmployeeID
    FROM Employees e
    WHERE e.EmployeeID IN (SELECT DISTINCT EmployeeID FROM Transactions)
    LIMIT 10
) e;
