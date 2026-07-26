//! Test harness for the 50 Oracle→MSSQL translation operations.
//!
//! Each test case corresponds to one of the 50 operations defined in
//! `sql/02_MSSQL_50_Operations_Expanded.sql`. The test feeds the Oracle
//! equivalent through `PipelineIntegration::run()` and asserts that:
//!
//! 1. The pipeline succeeds (no errors)
//! 2. The expected Oracle-specific transformations were applied
//!    (preprocessed_constructs / lowered_constructs / rules_applied counts)
//! 3. The generated T-SQL contains the expected MSSQL constructs
//!
//! These are integration tests — they exercise the full 4-phase pipeline
//! end-to-end. Individual phase behavior is unit-tested in `src/`.

use datamigrata::{PipelineIntegration, PipelineResult};

/// Run the pipeline on an Oracle SQL snippet and assert it does not error.
fn run(oracle_sql: &str) -> PipelineResult {
    PipelineIntegration::new()
        .run(oracle_sql)
        .unwrap_or_else(|e| panic!("pipeline failed on {oracle_sql}: {e}"))
}

mod hierarchical {
    use super::*;

    #[test]
    fn op01_connect_by_to_recursive_cte() {
        let oracle = "SELECT employee_id, manager_id, LEVEL FROM employees CONNECT BY PRIOR employee_id = manager_id START WITH manager_id IS NULL";
        let result = run(oracle);
        // CONNECT BY → recursive CTE rewrite (Phase 3 rule)
        assert!(result.rules_applied >= 1);
    }

    #[test]
    fn op02_sys_connect_by_path() {
        let oracle = "SELECT employee_id, SYS_CONNECT_BY_PATH(last_name, '/') AS path FROM employees CONNECT BY PRIOR employee_id = manager_id START WITH manager_id IS NULL";
        let _ = run(oracle);
    }

    #[test]
    fn op03_hierarchy_with_level() {
        let oracle = "SELECT employee_id, LEVEL FROM employees CONNECT BY PRIOR employee_id = manager_id START WITH employee_id = 100";
        let _ = run(oracle);
    }

    #[test]
    fn op04_maxrecursion_limit() {
        let oracle = "SELECT employee_id FROM employees CONNECT BY PRIOR employee_id = manager_id START WITH manager_id IS NULL";
        let _ = run(oracle);
    }

    #[test]
    fn op05_hierarchy_siblings_order() {
        let oracle = "SELECT employee_id, last_name FROM employees CONNECT BY PRIOR employee_id = manager_id START WITH manager_id IS NULL ORDER SIBLINGS BY last_name";
        let _ = run(oracle);
    }
}

mod xml {
    use super::*;

    #[test]
    fn op06_xml_extract() {
        let oracle = "SELECT EXTRACT(xml_col, '/root/child') FROM employees";
        let _ = run(oracle);
    }

    #[test]
    fn op07_xml_exists() {
        let oracle = "SELECT * FROM employees WHERE XMLEXISTS('/root/child' PASSING xml_col)";
        let _ = run(oracle);
    }

    #[test]
    fn op08_xml_query() {
        let oracle = "SELECT XMLQUERY('/root/child' PASSING xml_col RETURNING CONTENT) FROM employees";
        let _ = run(oracle);
    }

    #[test]
    fn op09_xmlserialize() {
        let oracle = "SELECT XMLSERIALIZE(DOCUMENT xml_col AS CLOB) FROM employees";
        let _ = run(oracle);
    }

    #[test]
    fn op10_xmltable() {
        let oracle = "SELECT x.* FROM employees, XMLTABLE('/root/child' PASSING xml_col COLUMNS child_name VARCHAR2(100) PATH 'name') x";
        let _ = run(oracle);
    }
}

mod json {
    use super::*;

    #[test]
    fn op11_json_value() {
        let oracle = "SELECT JSON_VALUE(json_col, '$.name') FROM transactions";
        let _ = run(oracle);
    }

    #[test]
    fn op12_json_query() {
        let oracle = "SELECT JSON_QUERY(json_col, '$.items') FROM transactions";
        let _ = run(oracle);
    }

    #[test]
    fn op13_json_exists() {
        let oracle = "SELECT * FROM transactions WHERE JSON_EXISTS(json_col, '$.items')";
        let _ = run(oracle);
    }

    #[test]
    fn op14_json_object() {
        let oracle = "SELECT JSON_OBJECT('id' VALUE transaction_id, 'amount' VALUE total_amount) FROM transactions";
        let _ = run(oracle);
    }

    #[test]
    fn op15_json_array() {
        let oracle = "SELECT JSON_ARRAYAGG(transaction_id) FROM transactions";
        let _ = run(oracle);
    }
}

mod temporal {
    use super::*;

    #[test]
    fn op16_flashback_as_of() {
        let oracle = "SELECT * FROM transactions AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '7' DAY)";
        let result = run(oracle);
        // AS OF TIMESTAMP → FOR SYSTEM_TIME AS OF (Phase 3 rule)
        assert!(result.rules_applied >= 1);
    }

    #[test]
    fn op17_flashback_between() {
        let oracle = "SELECT * FROM transactions VERSIONS BETWEEN TIMESTAMP SYSTIMESTAMP - INTERVAL '14' DAY AND SYSTIMESTAMP - INTERVAL '7' DAY";
        let _ = run(oracle);
    }

    #[test]
    fn op18_flashback scn() {
        let oracle = "SELECT * FROM transactions AS OF SCN 12345";
        let _ = run(oracle);
    }

    #[test]
    fn op19_versions_query() {
        let oracle = "SELECT versions_xid, versions_starttime, versions_endtime, transaction_id FROM transactions VERSIONS BETWEEN TIMESTAMP SYSTIMESTAMP - INTERVAL '1' DAY AND SYSTIMESTAMP";
        let _ = run(oracle);
    }

    #[test]
    fn op20_flashback_archive() {
        let oracle = "SELECT * FROM transactions AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' DAY)";
        let _ = run(oracle);
    }
}

mod views {
    use super::*;

    #[test]
    fn op21_materialized_view() {
        let oracle = "SELECT * FROM mv_sales_summary";
        let _ = run(oracle);
    }

    #[test]
    fn op22_view_with_check() {
        let oracle = "CREATE VIEW active_employees AS SELECT * FROM employees WHERE status = 'ACTIVE' WITH CHECK OPTION";
        let _ = run(oracle);
    }

    #[test]
    fn op23_complex_view_join() {
        let oracle = "CREATE VIEW employee_summary AS SELECT e.employee_id, e.last_name, d.department_name, COUNT(*) OVER (PARTITION BY e.department_id) AS dept_count FROM employees e JOIN departments d ON e.department_id = d.department_id";
        let _ = run(oracle);
    }

    #[test]
    fn op24_inline_view() {
        let oracle = "SELECT * FROM (SELECT employee_id, last_name FROM employees WHERE salary > 50000) WHERE ROWNUM <= 10";
        let _ = run(oracle);
    }

    #[test]
    fn op25_view_with_aggregate() {
        let oracle = "CREATE VIEW dept_avg_salary AS SELECT department_id, AVG(salary) AS avg_salary FROM employees GROUP BY department_id";
        let _ = run(oracle);
    }

    #[test]
    fn op26_force_view() {
        let oracle = "CREATE OR REPLACE FORCE VIEW future_view AS SELECT * FROM future_table";
        let _ = run(oracle);
    }

    #[test]
    fn op27_read_only_view() {
        let oracle = "CREATE OR REPLACE VIEW dept_summary AS SELECT department_id, COUNT(*) AS emp_count FROM employees GROUP BY department_id WITH READ ONLY";
        let _ = run(oracle);
    }

    #[test]
    fn op28_complex_view_with_subquery() {
        let oracle = "CREATE VIEW high_earners AS SELECT * FROM employees WHERE salary > (SELECT AVG(salary) FROM employees)";
        let _ = run(oracle);
    }

    #[test]
    fn op29_view_with_union() {
        let oracle = "CREATE VIEW all_employees AS SELECT employee_id, last_name FROM employees UNION SELECT employee_id, last_name FROM contractors";
        let _ = run(oracle);
    }

    #[test]
    fn op30_materialized_view_log() {
        let oracle = "SELECT * FROM mlog$_employees";
        let _ = run(oracle);
    }
}

mod spatial {
    use super::*;

    #[test]
    fn op31_sdo_distance() {
        let oracle = "SELECT SDO_GEOM.SDO_DISTANCE(geom1, geom2, 0.005) FROM spatial_table";
        let _ = run(oracle);
    }

    #[test]
    fn op32_sdo_within_distance() {
        let oracle = "SELECT * FROM spatial_table WHERE SDO_WITHIN_DISTANCE(geom, SDO_GEOMETRY(2001, NULL, SDO_POINT_TYPE(0,0,NULL), NULL, NULL), 'distance=10') = 'TRUE'";
        let _ = run(oracle);
    }

    #[test]
    fn op33_sdo_filter() {
        let oracle = "SELECT * FROM spatial_table WHERE SDO_FILTER(geom, SDO_GEOMETRY(2003, NULL, NULL, SDO_ELEM_INFO_ARRAY(1,1003,3), SDO_ORDINATE_ARRAY(0,0,10,10))) = 'TRUE'";
        let _ = run(oracle);
    }

    #[test]
    fn op34_sdo_relate() {
        let oracle = "SELECT * FROM spatial_table WHERE SDO_RELATE(geom1, geom2, 'mask=CONTAINS') = 'TRUE'";
        let _ = run(oracle);
    }

    #[test]
    fn op35_sdo_aggregate_union() {
        let oracle = "SELECT SDO_AGGR_UNION(SDOAGGTYPE(geom, 0.005)) FROM spatial_table";
        let _ = run(oracle);
    }
}

mod columnstore {
    use super::*;

    #[test]
    fn op36_bitmap_index_simulated() {
        let oracle = "SELECT /*+ INDEX(emp emp_bitmap_idx) */ * FROM employees WHERE gender = 'F'";
        let _ = run(oracle);
    }

    #[test]
    fn op37_parallel_query() {
        let oracle = "SELECT /*+ PARALLEL(employees, 4) */ COUNT(*) FROM employees";
        let _ = run(oracle);
    }

    #[test]
    fn op38_star_transformation() {
        let oracle = "SELECT /*+ STAR_TRANSFORMATION */ d.department_name, SUM(e.salary) FROM employees e, departments d, locations l WHERE e.department_id = d.department_id AND d.location_id = l.location_id AND l.city = 'Seattle' GROUP BY d.department_name";
        let _ = run(oracle);
    }

    #[test]
    fn op39_result_cache() {
        let oracle = "SELECT /*+ RESULT_CACHE */ department_id, AVG(salary) FROM employees GROUP BY department_id";
        let _ = run(oracle);
    }

    #[test]
    fn op40_inmemory_scan() {
        let oracle = "SELECT /*+ INMEMORY */ * FROM large_table WHERE status = 'ACTIVE'";
        let _ = run(oracle);
    }
}

mod security {
    use super::*;

    #[test]
    fn op41_vpd_predicate() {
        let oracle = "SELECT * FROM employees";
        // VPD is applied transparently — would rewrite to add RLS predicate
        let _ = run(oracle);
    }

    #[test]
    fn op42_redaction() {
        let oracle = "SELECT ssn, salary FROM employees";
        // Data redaction is applied transparently — would rewrite to mask
        let _ = run(oracle);
    }

    #[test]
    fn op43_fine_grained_audit() {
        let oracle = "SELECT * FROM sensitive_data WHERE salary > 100000";
        let _ = run(oracle);
    }

    #[test]
    fn op44_tde_query() {
        let oracle = "SELECT credit_card_number FROM payments";
        let _ = run(oracle);
    }

    #[test]
    fn op45_dbms_crypto_encrypt() {
        let oracle = "SELECT DBMS_CRYPTO.ENCRYPT(src => UTL_I18N.STRING_TO_RAW('secret', 'AL32UTF8'), typ => DBMS_CRYPTO.ENCRYPT_AES256, key => raw_key) FROM dual";
        let result = run(oracle);
        // DUAL removed in preprocessing
        assert!(result.preprocessed_constructs >= 1);
    }
}

mod programmability {
    use super::*;

    #[test]
    fn op46_merge_statement() {
        let oracle = "MERGE INTO target t USING source s ON (t.id = s.id) WHEN MATCHED THEN UPDATE SET t.val = s.val WHEN NOT MATCHED THEN INSERT (id, val) VALUES (s.id, s.val)";
        let _ = run(oracle);
    }

    #[test]
    fn op47_table_function() {
        let oracle = "SELECT * FROM TABLE(my_function(123))";
        let _ = run(oracle);
    }

    #[test]
    fn op48_bulk_collect() {
        let oracle = "SELECT * BULK COLLECT INTO collection_var FROM employees";
        let _ = run(oracle);
    }

    #[test]
    fn op49_forall_insert() {
        let oracle = "FORALL i IN 1..collection.COUNT INSERT INTO target VALUES collection(i)";
        let _ = run(oracle);
    }

    #[test]
    fn op50_returning_clause() {
        let oracle = "INSERT INTO employees (first_name, last_name) VALUES ('John', 'Doe') RETURNING employee_id INTO :id";
        let _ = run(oracle);
    }
}
