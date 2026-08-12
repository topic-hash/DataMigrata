-- OP 44 Variant B (Alternative approach): Maintain a DuckDB-native audit metadata table.
-- Assumes a table Audit.ServerAudits was created during migration to mirror sys.server_audits.
SELECT
    name,
    type_desc,
    on_failure,
    is_state_enabled,
    create_date,
    modify_date
FROM Audit.ServerAudits
LIMIT 50;
