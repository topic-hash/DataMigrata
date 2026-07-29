-- OP 49: SESSION_CONTEXT for cross-request state
-- Translated from T-SQL to DuckDB dialect

SELECT 
    NULL AS CurrentUserID,
    NULL AS CurrentDept,
    NULL AS CurrentSecLevel,
    'unknown' AS ServerLogin,
    'unknown' AS OriginalLogin,
    'duckdb' AS ApplicationName
