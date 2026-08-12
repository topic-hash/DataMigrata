-- OP 44 Variant C (Pre-computed/materialized): Assumes a view sys.server_audits
-- was created in DuckDB mapping to the Audit.ServerAudits table (or returning empty).
-- Schema (assumed):
--   CREATE VIEW sys.server_audits AS
--   SELECT name, type_desc, on_failure, is_state_enabled, create_date, modify_date
--   FROM Audit.ServerAudits;

SELECT name, type_desc, on_failure, is_state_enabled, create_date, modify_date
FROM sys.server_audits
LIMIT 50;
