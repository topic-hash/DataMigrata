-- OP 49: SESSION_CONTEXT for cross-request state
-- Translation: SESSION_CONTEXT keys set to 4, 'Engineering', 3; SUSER_SNAME='sa'; ORIGINAL_LOGIN='sa'; APP_NAME='SQLCMD'
SELECT
    4 AS CurrentUserID,
    'Engineering' AS CurrentDept,
    3 AS CurrentSecLevel,
    'sa' AS ServerLogin,
    'sa' AS OriginalLogin,
    'SQLCMD' AS ApplicationName
