-- OP 39: Real-time operational analytics with columnstore
SELECT TOP 50 Year, SUM(Amount) AS YearTotal, COUNT(*) AS TransactionCount
FROM Archive.OldTransactions 
GROUP BY Year 
ORDER BY Year;
GO

