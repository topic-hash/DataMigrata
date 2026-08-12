-- OP 25 Variant A (Direct translation): Inline TVF -> CTE with parameters inlined.
-- DuckDB has no parameterized TVF; inline the parameters @EmployeeID, @StartDate, @EndDate.
WITH params AS (
    SELECT
        6                       AS EmployeeID,
        TIMESTAMP '2026-01-01'  AS StartDate,
        TIMESTAMP '2026-12-31'  AS EndDate
),
fn_GetEmployeeSales AS (
    SELECT
        t.TransactionID,
        t.EmployeeID,
        e.FullName,
        t.TotalAmount,
        t.TransactionDate
    FROM Sales.Transactions t
    JOIN HR.Employees e ON e.EmployeeID = t.EmployeeID
    CROSS JOIN params p
    WHERE t.EmployeeID = p.EmployeeID
      AND t.TransactionDate BETWEEN p.StartDate AND p.EndDate
)
SELECT *
FROM fn_GetEmployeeSales
ORDER BY TransactionDate
LIMIT 50;
