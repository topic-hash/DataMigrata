-- OP 49: SESSION_CONTEXT for cross-request state
EXEC sp_set_session_context 'UserEmployeeID', 4;
EXEC sp_set_session_context 'Department', 'Engineering';
EXEC sp_set_session_context 'SecurityLevel', 3;

SELECT 
    SESSION_CONTEXT(N'UserEmployeeID') AS CurrentUserID,
    SESSION_CONTEXT(N'Department') AS CurrentDept,
    SESSION_CONTEXT(N'SecurityLevel') AS CurrentSecLevel,
    SUSER_SNAME() AS ServerLogin,
    ORIGINAL_LOGIN() AS OriginalLogin,
    APP_NAME() AS ApplicationName;
GO

