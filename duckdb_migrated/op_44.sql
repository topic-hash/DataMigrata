-- OP 44: Audit specification for compliance
-- Translated from T-SQL to DuckDB dialect

-- (Audit created during migration;
query the audit file if configured)
SELECT * FROM sys.server_audits
LIMIT 50
