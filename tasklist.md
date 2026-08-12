# DataMigrata — Master Task List

**Ultimate DoD**: 50/50 ops PASS in `best_config/verification_log.csv`, 3 schema variants each 50/50 PASS, combinatorial search complete, FINAL_REPORT.md written, best_config packaged, TDS server runnable.

**Reporting format**: `[Wave X, Task Y] [PASS=XX/50] [Tasks: XX/103]`

---

## Wave 0 — Discovery (COMPLETE)
- [x] 001 Clone DataMigrata repo
- [x] 002 Explore codespacectl tool
- [x] 003 Verify 3 codespaces ("studious halibut", "symmetrical tribble", "symmetrical invention")
- [x] 004 Document repo structure (sql/, docker/, src/, etc.)
- [x] 005 Write discovery_report.md

## Wave 1 — Ground Truth & Baseline (COMPLETE)
- [x] 006 Stand up MSSQL container (mssql-server-linux:2022-latest)
- [x] 007 Load 01_MSSQL_Migration_SyntheticData.sql
- [x] 008 Load 01_MSSQL_Populate_Data_SetBased.sql
- [x] 009 Load 02_MSSQL_50_Operations_Expanded.sql
- [x] 010 Capture 50 ops as gold_standard/op_NN.csv with MD5
- [x] 011 Capture MSSQL energy profile (50/50 ops, joules per op)
- [x] 012 Run DuckDB baseline (unmodified T-SQL)
- [x] 013 Write baseline_report.md

## Wave 2 — Compiler Skeleton (COMPLETE)
- [x] 014 Cargo workspace with 6 crates
- [x] 015 T-SQL parser → AST (sqlparser-rs)
- [x] 016 AST → DataFusion LogicalPlan lowering
- [x] 017 Catalog trait (3 schema variants)
- [x] 018 16/16 Rust unit tests pass
- [x] 019 Codemodel module (energy constants)
- [x] 020 Optimizer scaffold (rewrite rule registry)

## Wave 3 — First Rewrite Rule & Code Generation (PARTIAL)
- [x] 021 Choose failing op (op 1: HIERARCHYID recursive CTE)
- [x] 022 Implement rewrite rule (HIERARCHYID → recursive CTE)
- [x] 023 Implement DuckDB SQL code generator
- [x] 024 Execute against DuckDB
- [x] 025 Hash-match against gold → PASS
- [x] 026 Measure energy (cpu_joules, dram_joules)
- [x] 027 Record in verification_log.csv
- [x] 028 Commit [Wave 3 Task 1]

## Wave 4 — Full Rewrite Coverage (IN PROGRESS — 16/50 PASS)
- [x] 029 Op 1 PASS (recursive CTE)
- [x] 030 Op 3 PASS
- [x] 031 Op 4 PASS
- [x] 032 Op 9 PASS
- [x] 033 Op 10 PASS
- [x] 034 Op 13 PASS
- [x] 035 Op 14 PASS
- [x] 036 Op 35 PASS
- [x] 037 Op 39 PASS
- [x] 038 Op 40 PASS
- [x] 039 Op 41 PASS
- [x] 040 Op 42 PASS
- [x] 041 Op 43 PASS
- [x] 042 Op 44 PASS
- [x] 043 Op 48 PASS
- [x] 044 Op 49 PASS
- [ ] 045 Build unified verify_ops.py with datetime2(7) formatting
- [ ] 046 Re-export MSSQL data with proper datetime2 handling (normalize gold)
- [ ] 047 Op 2  PASS (datetime2 precision fix)
- [ ] 048 Op 5  PASS (recursive CTE ordering)
- [ ] 049 Op 6  PASS (XML: nodes/value → JSON extract)
- [ ] 050 Op 7  PASS (XML: query() → JSON extract_path)
- [ ] 051 Op 8  PASS (XML FOR XML PATH → JSON aggregation)
- [ ] 052 Op 11 PASS (column ordering / NULL handling)
- [ ] 053 Op 12 PASS (JSON_ARRAY vs DuckDB json_array)
- [ ] 054 Op 15 PASS (json_extract_array → unnest with cast)
- [ ] 055 Op 16 PASS (VARCHAR→TIMESTAMP cast for ValidFrom)
- [ ] 056 Op 17 PASS (VARCHAR→TIMESTAMP cast)
- [ ] 057 Op 18 PASS (datediff signature)
- [ ] 058 Op 19 PASS (VARCHAR→TIMESTAMPTZ cast)
- [ ] 059 Op 20 PASS (datediff signature)
- [ ] 060 Op 21 PASS (decimal precision SUM)
- [ ] 061 Op 22 PASS (VARCHAR→TIMESTAMP cast)
- [ ] 062 Op 23 PASS (column projection / ORDER BY)
- [ ] 063 Op 24 PASS (datetime2 computed)
- [ ] 064 Op 25 PASS (datetime2 + NULL formatting)
- [ ] 065 Op 26 PASS (NULL → empty in SUM)
- [ ] 066 Op 27 PASS (NULL → empty in SUM)
- [ ] 067 Op 28 PASS (recursive manager ordering)
- [ ] 068 Op 29 PASS (decimal precision 17,8 vs 17,10)
- [ ] 069 Op 30 PASS (datetime2 LAG window)
- [ ] 070 Op 31 PASS (spatial distance — bounding box)
- [ ] 071 Op 32 PASS (spatial distance — haversine)
- [ ] 072 Op 33 PASS (spatial centroid)
- [ ] 073 Op 34 PASS (spatial aggregate)
- [ ] 074 Op 36 PASS (datetime2 group-by)
- [ ] 075 Op 37 PASS (datetime2 00:00:00.0000000 format)
- [ ] 076 Op 38 PASS (datetime2 HighSpeedLookup)
- [ ] 077 Op 45 PASS (TOP 100 → LIMIT 100)
- [ ] 078 Op 46 PASS (datetime2 formatting)
- [ ] 079 Op 47 PASS (decimal precision)
- [ ] 080 Op 50 PASS (datetime2 final)
- [ ] 081 verification_log.csv shows 50/50 PASS
- [ ] 082 3+ alternatives implemented per gap class (XML, spatial, temporal)

## Wave 5 — Schema Variants
- [ ] 083 Schema A (baseline): tables as-is, no precomputation
- [ ] 084 Schema A: 50/50 PASS
- [ ] 085 Schema B (columnar-optimized): reorder columns, type tightening
- [ ] 086 Schema B: 50/50 PASS
- [ ] 087 Schema C (pre-computed): materialized paths, bbox, caches
- [ ] 088 Schema C: 50/50 PASS
- [ ] 089 schema_benchmark_report.md updated with all 3 variants

## Wave 6 — Combinatorial Optimization Search
- [ ] 090 Search harness (op × schema × rewrite × alternative)
- [ ] 091 Energy measurement per config
- [ ] 092 search_results.csv populated
- [ ] 093 Identify global optimum

## Wave 7 — Final Report & Delivery
- [ ] 094 FINAL_REPORT.md with energy analysis
- [ ] 095 best_config/ packaged (SQL + schema + runner)
- [ ] 096 verification_log.csv final (50/50 PASS, joules per op)
- [ ] 097 discovery_report.md final
- [ ] 098 baseline_report.md final
- [ ] 099 schema_benchmark_report.md final
- [ ] 100 search_results.csv final
- [ ] 101 TDS server skeleton (listeners, op dispatch)
- [ ] 102 All commits pushed as topic-hash
- [ ] 103 Ultimate DoD: every checkbox above [x]
