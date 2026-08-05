-- OP 44 Variant A (Direct translation): sys.server_audits does not exist in DuckDB; return empty result set.
-- Return no rows with a compatible schema so downstream code keeps working.
SELECT
    CAST(NULL AS VARCHAR)  AS name,
    CAST(NULL AS VARCHAR)  AS type_desc,
    CAST(NULL AS VARCHAR)  AS on_failure,
    CAST(NULL AS BOOLEAN)  AS is_state_enabled,
    CAST(NULL AS TIMESTAMP) AS create_date,
    CAST(NULL AS TIMESTAMP) AS modify_date
WHERE 1 = 0;
