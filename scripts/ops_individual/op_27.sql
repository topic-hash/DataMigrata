-- OP 27: View with UNPIVOT for normalization
SELECT TOP 50 * FROM Sales.vw_NormalizedQuarterlySales 
WHERE Amount IS NOT NULL
ORDER BY EmployeeID, Quarter;
GO

