-- OP 37: Natively compiled stored procedure
SELECT * FROM Sales.CustomerCache
ORDER BY LastOrderDate DESC, CustomerID
LIMIT 100
