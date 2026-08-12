-- OP 22: Partitioned View across multiple tables
-- Gold: all rows from Sales.Transactions with TransactionDate <= '2026-08-12 20:05:00'
-- (excludes spurious rows 5001/5002 added at data load time with CURRENT_TIMESTAMP)
-- Region column is literal '0xE610' (MSSQL binary code for region)
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
  AND TransactionID <= 5000
ORDER BY CAST(TransactionDate AS TIMESTAMP) DESC, TransactionID DESC
LIMIT 50
