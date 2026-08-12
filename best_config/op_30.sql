-- OP 30: View with window functions and framing
SELECT
    FullName,
    TransactionDate,
    CAST(TotalAmount AS DECIMAL(36,8)) AS TotalAmount,
    CAST(RunningTotal AS DECIMAL(36,8)) AS RunningTotal,
    SalesRank,
    CAST(PrevAmount AS DECIMAL(36,8)) AS PrevAmount,
    CAST(NextAmount AS DECIMAL(36,8)) AS NextAmount
FROM Sales.vw_RunningTotalsAndRanks
ORDER BY FullName, TransactionDate
LIMIT 100
