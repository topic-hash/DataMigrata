-- OP 13 Variant A (Direct translation): JSON_MODIFY -> json_set
-- First update: set $.processed = true where it is null.
UPDATE Sales.Transactions
SET TransactionDetails = json_set(TransactionDetails, '$.processed', TRUE)
WHERE json_extract(TransactionDetails, '$.processed') IS NULL;

-- Equivalent of UPDATE TOP (100): limit using a CTE+row_number or subquery in DuckDB.
-- DuckDB does not support UPDATE ... LIMIT directly; do a limited update via a CTE.
WITH to_update AS (
    SELECT TransactionID
    FROM Sales.Transactions
    WHERE json_extract(TransactionDetails, '$.processed') IS NULL
    LIMIT 100
)
UPDATE Sales.Transactions
SET TransactionDetails = json_set(TransactionDetails, '$.processed', TRUE)
WHERE TransactionID IN (SELECT TransactionID FROM to_update);

-- Second update: append 'high_value' to $.tags array for high-value transactions.
WITH to_tag AS (
    SELECT TransactionID
    FROM Sales.Transactions
    WHERE TotalAmount > 50000
    LIMIT 50
)
UPDATE Sales.Transactions
SET TransactionDetails = json_set(
    TransactionDetails,
    '$.tags',
    CASE
        WHEN json_type(TransactionDetails, '$.tags') = 'ARRAY'
            THEN array_append(
                json_extract(TransactionDetails, '$.tags')::VARCHAR[],
                'high_value'
            )
        ELSE ['high_value']
    END
)
WHERE TransactionID IN (SELECT TransactionID FROM to_tag);

SELECT TransactionID, TotalAmount, TransactionDetails
FROM Sales.Transactions
LIMIT 20;
