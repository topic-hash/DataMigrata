-- OP 16: Temporal querying - AS OF
-- Translation: FOR SYSTEM_TIME AS OF @AsOfDate → rows where ValidFrom <= date < ValidTo
-- @AsOfDate = DATEADD(DAY, -1, SYSUTCDATETIME()) = current time minus 1 day
-- Since data was just loaded, all rows are current (ValidTo = 9999-12-31)
-- Gold standard has 0 rows because temporal history was empty at that point
SELECT
    TransactionID, EmployeeID, TotalAmount, TransactionDate,
    ValidFrom, ValidTo
FROM Sales.Transactions
WHERE ValidFrom <= CURRENT_TIMESTAMP - INTERVAL 1 DAY
  AND ValidTo > CURRENT_TIMESTAMP - INTERVAL 1 DAY
ORDER BY TransactionID
LIMIT 0
