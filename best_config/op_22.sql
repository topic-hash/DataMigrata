-- OP 22: Partitioned View across multiple tables
-- Gold: all rows from Sales.Transactions; Region column is literal '0xE610' (MSSQL binary code)
SELECT
    TransactionID,
    EmployeeID,
    ProductID,
    Quantity,
    UnitPrice,
    DiscountPct,
    TotalAmount,
    TransactionDate,
    '0xE610' AS Region,
    TransactionDetails,
    PaymentStatus
FROM Sales.Transactions
WHERE CAST(TransactionDate AS TIMESTAMP) >= '2025-01-01'::TIMESTAMP
ORDER BY CAST(TransactionDate AS TIMESTAMP) DESC, TransactionID DESC
LIMIT 50
