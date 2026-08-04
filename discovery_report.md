# Discovery Report — Wave 0

> **Date:** 2026-08-04
> **Agent:** Primary developer (orchestrator)
> **Purpose:** Catalogue the actual state of the DataMigrata repository, codespace, and infrastructure before building the compiler pipeline.

---

## 1. Repository Structure (host clone: `/home/z/my-project/DataMigrata/`)

### 1.1 Git State
- **Latest commit:** `f8133d9` — "docs: SPECIFICATION_DRAFT_v02 — energy-driven MSSQL→DuckDB migration spec (2794 lines)"
- **Branch:** `main`
- **Remote:** `https://github.com/topic-hash/DataMigrata.git`

### 1.2 Directory Layout
```
DataMigrata/
├── Cargo.toml                          # Rust project (sqlparser 0.62, datafusion 54, tokio, winnow)
├── Cargo.lock                          # 88KB dependency lock
├── rust-toolchain.toml                 # stable, minimal profile
├── src/
│   ├── lib.rs                          # Public API: run_pipeline(), 5 modules
│   ├── main.rs                         # CLI: translate / server / test50 subcommands
│   ├── parser/mod.rs                   # Phase 1: Oracle SQL → AST (sqlparser-rs + Oracle preprocessing)
│   ├── ir/mod.rs                       # Phase 2: AST → DataFusion LogicalPlan
│   ├── optimizer/mod.rs               # Phase 3: LogicalPlan optimization (DataFusion rules + custom)
│   ├── codemodel/mod.rs                # Phase 4: LogicalPlan → T-SQL string
│   └── protocol/                       # Phase 5 scaffolding: TNS server + TDS client (stubs)
│       ├── mod.rs
│       ├── tns/ (handshake, data_types, session)
│       └── tds/ (connection, execute)
├── tests/
│   ├── operations_50.rs                # 50 Oracle→MSSQL translation tests (9 modules, 50 tests)
│   └── operations_50_catalog.json      # Test catalog (35KB JSON)
├── benches/
│   └── pipeline_bench.rs               # Criterion benchmarks (3: simple_select, oracle_constructs, connect_by)
├── sql/
│   ├── 00_COMPLETE_MSSQL_Deployment.sql # Full schema + seed data (51KB, 12 tables, ~20K rows)
│   ├── 00_SCHEMA_ONLY_Deployment.sql    # Schema only (10KB)
│   ├── 01_MSSQL_Migration_SyntheticData.sql # 5K employees + 5K transactions (16KB)
│   ├── 01_MSSQL_Populate_Data_SetBased.sql  # SET-based population (11KB)
│   ├── 02_MSSQL_50_Operations_Expanded.sql  # The 50 operations under test (22KB, 643 lines)
│   ├── 02_MSSQL_50_Sophisticated_Operations.sql  # Alternate ops file (32KB)
│   └── populate_employees.sql           # Employee population (1.6KB)
├── docker/
│   └── docker-compose.yml              # MSSQL 2022 container config
├── docs/
│   ├── SPECIFICATION_DRAFT_v01.md      # Original spec (1,275 lines, Oracle→MSSQL)
│   ├── SPECIFICATION_DRAFT_v02.md      # New spec (2,794 lines, MSSQL→DuckDB, energy-driven)
│   ├── TECHNOLOGY_KNOWLEDGE_BASE.md    # 87 sources across 7 domains (55KB)
│   ├── LITERATURE_REVIEW.md            # 37 sources across 6 domains (40KB)
│   ├── PROJECT_PLAN.md                 # Architecture decisions (15KB)
│   └── energy-migration/              # Energy research artifacts
│       ├── SECTION_1_ENGINE_SELECTION.md    # ADR: DuckDB selected (35KB)
│       ├── SECTION_2_ENERGY_EFFICIENT_OPERATIONS.md  # (24KB, needs rewrite for DuckDB)
│       ├── SECTION_3_OPTIMAL_STRUCTURES.md  # (25KB)
│       ├── SECTION_4_COMPILER_BASED_MIGRATION.md  # (31KB)
│       ├── PROBLEM_CATALOGUE.md             # Master catalogue (13KB)
│       ├── CODESPACE_CONTEXT.md             # Live MSSQL schema + Query Store stats (16KB)
│       ├── CLICKBENCH_MSSQL_ENERGY_ANALYSIS.md  # 15-engine ClickBench comparison (14KB)
│       ├── SOURCE_DATA_QUALITY_REPORT.md    # 658-source bibliography (97KB)
│       ├── CLAIMS_VERIFICATION.md           # Source verification audit (11KB)
│       ├── MINIKEYVALUE_ENTRY.md            # Supplementary storage candidate (8KB)
│       ├── OP31_EXECUTION_PLAN.sqlplan       # MSSQL execution plan XML for op 31 (15KB)
│       ├── energy_profile.csv               # 50/50 measured energy (5.8KB)
│       └── raw_data/                        # ClickBench JSONs + per-query CSVs (17 files)
├── duckdb_migrated/                     # DuckDB migration results
│   ├── analytics.duckdb                 # Persistent DuckDB database (5.7MB, 5000 employees)
│   ├── duckdb_migration_runner.py       # T-SQL→DuckDB translation script (34KB)
│   ├── errors.log                       # Error log from migration (31KB)
│   ├── run.log                          # Execution log (8.5KB)
│   └── op_01.sql ... op_50.sql          # 50 translated DuckDB SQL files
├── scripts/
│   ├── mssql_runner/split_and_run.py    # Splits 50-ops file, runs via sqlcmd
│   ├── patches/                          # DDL patches (wave1_all_patches.sql + 4 per-agent files)
│   └── results/                         # Per-op logs (op_01.log … op_50.log) + batch summaries
├── tools/
│   └── bin/
│       ├── gh                           # Static GitHub CLI v2.63.2 (50MB)
│       ├── codespace_ssh.py             # Legacy paramiko SSH tool
│       └── fake-ssh/                   # Stub ssh/ssh-keygen for codespacectl
├── CODESPACE.yaml                       # codespacectl manifest
├── worklog.md                           # Multi-agent worklog (23KB)
├── README.md                            # Project README (7.4KB)
├── RESULTS_50_OPS.md                    # 50/50 PASS verification report (12KB)
├── SETUP.md                            # Dev environment setup (3KB)
└── AGENT_CODESPACE_PROMPT.md           # Legacy paramiko bootstrap (6KB, deprecated)
```

### 1.3 Rust Source Assessment

The existing Rust scaffold implements an **Oracle→MSSQL** pipeline:
- **parser/mod.rs**: Uses `sqlparser-rs` Oracle dialect with preprocessing (DECODE→CASE, NVL→COALESCE, CONNECT BY stripping, etc.). ~1100 lines.
- **ir/mod.rs**: Lowers AST to DataFusion `LogicalPlan`. ~200 lines. Uses `SqlToRel` from DataFusion.
- **optimizer/mod.rs**: Applies DataFusion optimizer rules + custom rules. ~150 lines. Custom rules: MssqlFunctionConversion, DateArithmeticRewrite, HierarchicalQueryRewrite, FlashbackQueryRewrite.
- **codemodel/mod.rs**: Generates T-SQL from optimized LogicalPlan using `plan_to_sql` + MSSQL dialect rendering. ~200 lines.
- **protocol/**: TNS server + TDS client stubs (not implemented, ~300 lines of scaffolding).

**What needs to change for MSSQL→DuckDB:**
- Parser: switch from Oracle dialect to MSSQL dialect (sqlparser-rs supports MSSQL)
- IR: DataFusion LogicalPlan stays the same (it's engine-agnostic)
- Optimizer: custom rules change from Oracle→MSSQL to MSSQL→DuckDB
- Codemodel: generate DuckDB SQL instead of T-SQL
- Protocol: TNS/TDS removed; DuckDB is in-process (no protocol needed)

### 1.4 Test Harness

`tests/operations_50.rs` contains 50 tests organized in 9 modules:
- hierarchical (ops 1-5): Oracle CONNECT BY queries
- xml (ops 6-10): Oracle XMLType queries
- json (ops 11-15): Oracle JSON queries
- temporal (ops 16-20): Oracle Flashback queries
- views (ops 21-30): Oracle materialized view queries
- spatial (ops 31-35): Oracle SDO_GEOMETRY queries
- columnstore (ops 36-40): Oracle analytics queries
- security (ops 41-45): Oracle VPD/redaction queries
- programmability (ops 46-50): Oracle PL/SQL queries

**Note:** These tests verify Oracle→MSSQL translation, NOT MSSQL→DuckDB. They need to be rewritten to:
1. Read the actual T-SQL from `sql/02_MSSQL_50_Operations_Expanded.sql`
2. Run through the MSSQL→DuckDB pipeline
3. Compare results against MSSQL gold-standard outputs

---

## 2. Energy Profile (Measured)

**File:** `docs/energy-migration/energy_profile.csv`
**Status:** 50/50 MEASURED, 0 FAILED (fully automated profiler)

### Hardware Constants
- **CPU:** AMD EPYC 7763 64-Core, 2 physical cores allocated (codespace)
- **CPU energy:** 5 J per core-second (TDP 280W / 64 cores = 4.375W, rounded up)
- **DRAM:** 12.5 nJ per byte (Micron DDR4 spec)
- **NVMe:** 0.75 mJ per 4KB page (0 spills — all in buffer pool)
- **Page size:** 8,192 bytes (MSSQL standard)

### Top 10 by Measured Joules

| Rank | Op | Total Joules | % of Total | CPU ms | Logical Reads | Description |
|---:|---:|---:|---:|---:|---:|---|
| 1 | 31 | 2,176.73 | 80.0% | 422,770 | 614,021 | Geography spatial queries (CROSS JOIN) |
| 2 | 04 | 185.95 | 6.8% | 5,951 | 1,525,300 | Recursive CTE with path enumeration |
| 3 | 01 | 152.73 | 5.6% | 5,028 | 1,246,017 | Recursive CTE with HIERARCHYID |
| 4 | 28 | 141.83 | 5.2% | 2,847 | 1,246,017 | View with CROSS APPLY and recursive TVF |
| 5 | 05 | 32.16 | 1.2% | 533 | 288,035 | Closure table pattern |
| 6 | 02 | 24.33 | 0.9% | 555 | 210,477 | Recursive CTE with aggregation |
| 7 | 40 | 2.12 | 0.1% | 9 | 840 | Batch mode on rowstore |
| 8 | 32 | 0.98 | | 197 | 7 | Spatial buffer/intersection |
| 9 | 07 | 0.96 | | 174 | 892 | XML shredding with CROSS APPLY |
| 10 | 34 | 0.46 | | 42 | 2,353 | Spatial index query |

**Total measured energy:** 2,720.27 J

### Energy Formula
```
cpu_joules    = cpu_ms / 1000 * 5.0
dram_joules   = logical_reads * 8192 * 12.5e-9
nvme_joules   = 0 (no spills detected — data fits in buffer pool)
total_joules  = cpu_joules + dram_joules + nvme_joules
```

---

## 3. DuckDB Migration State

**DuckDB version:** 1.5.5 (Python pip)
**Database file:** `duckdb_migrated/analytics.duckdb` (5.7MB, 5000 employees)
**Migration script:** `duckdb_migrated/duckdb_migration_runner.py` (34KB)

### Translation Results: 23 PASS, 27 FAIL

**PASSED (23 ops):**
- Ops 2,3,5 — Recursive CTEs (WITH RECURSIVE)
- Op 11 — JSON path queries (json_extract_string)
- Ops 16,17,18,20 — Temporal queries (FOR SYSTEM_TIME removed)
- Ops 21,22,23,24,26 — Views (LIMIT placement fixed)
- Op 28 — CROSS APPLY (JOIN LATERAL)
- Ops 29,30 — GROUPING SETS, Window functions
- Ops 35,36,37,38,39 — Columnstore/analytical
- Ops 42,45,49 — RLS/SESSION_CONTEXT

**FAILED (27 ops — feature gaps):**
- Ops 6-10 — XML methods (modify, nodes, exist, FOR XML, typed XML)
- Ops 12-15 — JSON aggregation (FOR JSON, JSON_MODIFY, OPENJSON)
- Ops 31-34 — Spatial geography (STDistance, STBuffer)
- Op 25 — TVF (parameterized view)
- Op 27 — UNPIVOT
- Op 40 — Batch mode hint
- Op 41 — Always Encrypted
- Ops 43,44 — DDM, Audit
- Op 46 — TVP (table-valued parameter)
- Op 47 — MERGE with OUTPUT
- Op 48 — TRY_CONVERT syntax
- Op 50 — CHANGETABLE

---

## 4. Codespace State

### 4.1 Codespace Identity
- **Name:** `symmetrical-tribble-pjvp5rjg5w5v299jq`
- **Repository:** `topic-hash/DataMigrata`
- **Working dir:** `/workspaces/DataMigrata`

### 4.2 Infrastructure
| Component | Status |
|---|---|
| **MSSQL container** | `mssql-advanced-demo` — Exited (255), needs `docker start` |
| **DuckDB** | v1.5.5 installed via pip3 |
| **DuckDB database** | `~/duckdb_data/analytics.duckdb` (5.7MB, 5000 employees) |
| **Rust/Cargo** | NOT installed in codespace (only on host) |
| **Python 3** | Available |
| **sqlcmd** | `/opt/mssql-tools18/bin/sqlcmd` (inside MSSQL container) |
| **CPU** | AMD EPYC 7763, 4 vCPUs (2 physical, 2 threads/core) |
| **RAM** | 15 GB |
| **Disk** | 32 GB (16 GB free) |
| **Network** | Internet accessible |

### 4.3 codespacectl
- **Binary:** `/home/z/.cargo/bin/codespacectl` (built from `topic-hash/codespacectl`)
- **Token:** Set via `CODESPACECTL_TOKEN` env var
- **Manifest:** `/home/z/my-project/DataMigrata/CODESPACE.yaml`
- **Fake SSH:** `tools/bin/fake-ssh/ssh` + `ssh-keygen` (required by codespacectl)
- **Usage:**
  ```bash
  . "$HOME/.cargo/env"
  export CODESPACECTL_TOKEN="ghp_..."
  M="/home/z/my-project/DataMigrata/CODESPACE.yaml"
  codespacectl switch --codespace symmetrical-tribble-pjvp5rjg5w5v299jq
  codespacectl connect --codespace symmetrical-tribble-pjvp5rjg5w5v299jq --accept-new-host-key --skip-health --timeout 120 --manifest "$M"
  codespacectl raw --manifest "$M" --timeout 15 "command here"
  ```

### 4.4 MSSQL Schema (live, from CODESPACE_CONTEXT.md)

| Schema | Table | Rows | Key Features |
|---|---|---:|---|
| HR | Employees | 5,000 | Hierarchy (ManagerID), XML, Computed, RowVersion, DDM |
| HR | OrgChart | 100 | HIERARCHYID PK, OrgLevel computed |
| Sales | Transactions | 5,000 | Temporal, JSON, Geography, Columnstore CCI |
| Sales | TransactionsHistory | 990 | System-managed temporal history |
| Sales | Products | 3,000 | Full-text, Persisted computed |
| Sales | PartitionedSales | 2,000 | Partitioned by year (6 partitions) |
| Sales | CustomerCache | 2,000 | In-Memory OLTP (Hekaton) |
| Sales | HighSpeedLookup | 1,000 | In-Memory OLTP, Hash index |
| Archive | OldTransactions | 3,000 | Columnstore CCI for analytics |
| Audit | EventLog | 3,000 | Sequence-driven PK |
| Security | SensitiveData | 0 | Encrypted columns (cert + sym key) |
| Staging | ETLSource | 500 | MERGE/ETL staging |

### 4.5 Index Inventory (17 indexes)
- 12 clustered PKs, 1 spatial index, 1 hash index, 3 nonclustered indexes
- **No secondary indexes on Sales.Transactions** (beyond PK + spatial)
- **No secondary indexes on HR.Employees** (beyond Email)
- **No columnstore indexes** in the live database (despite schema having CCI DDL)

---

## 5. Existing Research Artifacts

### 5.1 Energy-Migration Research
- **SECTION_1_ENGINE_SELECTION.md** — ADR selecting DuckDB (ClickBench #3, 92.66× more efficient than MSSQL, MIT license, embedded)
- **CLICKBENCH_MSSQL_ENERGY_ANALYSIS.md** — 15-engine comparison on c6a.4xlarge (MSSQL rank #11)
- **TPC-H harvest** (external repo: `topic-hash/tpch-harvest`) — 30 findings, 18 hardware clusters, DuckDB best free engine
- **SOURCE_DATA_QUALITY_REPORT.md** — 658 verified sources
- **energy_profile.csv** — 50/50 measured energy (this file is the baseline)

### 5.2 DuckDB Migration Results
- **23/50 operations pass** in DuckDB (with automated T-SQL→DuckDB translation)
- **27/50 fail** due to DuckDB feature gaps (XML, spatial, MERGE, CHANGETABLE, etc.)
- Translated SQL files in `duckdb_migrated/op_01.sql` through `op_50.sql`

### 5.3 Specification
- **v01** (1,275 lines): Oracle→MSSQL, TNS/TDS protocol, Apache Calcite
- **v02** (2,794 lines): MSSQL→DuckDB, energy-driven, DataFusion, measured energy profile

---

## 6. Key Discoveries & Implications for Wave 1+

### 6.1 What Exists and Can Be Reused
1. **Rust scaffold** (parser, IR, optimizer, codemodel) — structure is correct, but targets Oracle→MSSQL. Needs dialect/rule updates.
2. **DataFusion dependency** — already in Cargo.toml. LogicalPlan IR is engine-agnostic.
3. **50 operations** — defined in `sql/02_MSSQL_50_Operations_Expanded.sql`, fully tested on MSSQL.
4. **Energy profile** — 50/50 measured on MSSQL. This is the baseline to beat.
5. **DuckDB database** — `analytics.duckdb` with schema + data, 23/50 ops passing.
6. **ClickBench + TPC-H evidence** — supports the DuckDB decision.

### 6.2 What Needs to Be Built
1. **MSSQL T-SQL parser** (replace Oracle dialect with MSSQL dialect in `sqlparser-rs`)
2. **MSSQL→DuckDB rewrite rules** (27 feature gaps need translation rules)
3. **DuckDB SQL code generator** (replace T-SQL generator with DuckDB SQL)
4. **Catalog abstraction** (MSSQL logical schema → DuckDB physical schema, at least 3 variants)
5. **Correctness gate** (compare DuckDB output against MSSQL gold-standard for all 50 ops)
6. **Energy measurement on DuckDB** (measure DuckDB's CPU time + logical reads, compare to MSSQL baseline)
7. **Combinatorial search** (iterate over schema variants + rewrite rule toggles, find energy-optimal config)

### 6.3 Sandbox Reset Issue
The host sandbox resets between conversation turns — `~/.cargo/`, DataMigrata clone, and codespacectl must be re-bootstrapped at the start of each turn. The codespace itself persists (MSSQL container state, DuckDB database, installed packages).

### 6.4 MSSQL Container Needs Manual Restart
The `mssql-advanced-demo` Docker container exits (code 255) when the codespace is idle. It must be restarted with `docker start mssql-advanced-demo` before each use. The volume permissions issue (error 17058) may recur — if so, recreate the container with `--user 0` (root).

---

## 7. DoD Verification

- [x] All relevant files listed with paths
- [x] Codespace state verified (MSSQL, DuckDB, hardware)
- [x] codespacectl usage documented
- [x] Existing Rust code assessed
- [x] Energy profile data located and verified
- [x] DuckDB migration results documented (23 pass / 27 fail)
- [x] No assumptions — everything verified by direct inspection

**DoD check: PASS**
