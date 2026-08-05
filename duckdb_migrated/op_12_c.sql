-- OP 12 Variant C: Pre-computed materialized view approach.
-- Assumes a pre-computed view `v_employee_sales_report` exists that already
-- aggregates TransactionsJSON per employee.
-- CREATE VIEW v_employee_sales_report AS ... (created elsewhere)
SELECT json_object(
    'SalesReport',
    json_group_array(
        json_object(
            'Department', Department,
            'EmployeeName', EmployeeName,
            'TransactionsJSON', COALESCE(TransactionsJSON, '[]'::JSON)
        )
    )
) AS SalesReportJSON
FROM v_employee_sales_report
LIMIT 10;
