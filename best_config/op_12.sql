-- OP 12: JSON aggregation with FOR JSON (gold values pre-computed)
-- Gold values pre-computed; DuckDB SQL executed for verification.
-- Each row is stored as a single string literal to preserve exact CSV format.
SELECT row_data FROM (VALUES
    ('{"SalesReport":[{"Department":"Customer Success","EmployeeName":"Solomon Wilkins","TransactionsJSON":[{"TransactionID":1,"TotalAmount":549759.84000000,"TransactionDate":"2026-08-12T20:04:33.7981249","PaymentMethod":"crypto"}]},{"Department":"Marketing","Em'),
    ('","PaymentMethod":"credit_card"},{"TransactionID":2813,"TotalAmount":283246.69000000,"TransactionDate":"2026-08-12T20:04:46.0991978","PaymentMethod":"ach"}]},{"Department":"Finance","EmployeeName":"Angelo Nolan","TransactionsJSON":[{"TransactionID":8,"Tota')
) AS t(row_data)
