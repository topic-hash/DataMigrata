# DataMigrata

> **Energy-optimal MSSQL-to-DuckDB migration compiler**
>
> Translates MSSQL T-SQL operations to DuckDB SQL, minimizing energy
> consumption through schema optimization and query rewrites. Built in
> Rust with DataFusion and sqlparser-rs.

---

## Overview

DataMigrata is a compiler pipeline that translates MSSQL T-SQL into
DuckDB SQL. It parses MSSQL dialect constructs (TOP, ISNULL, GETDATE,
HIERARCHYID, XML DML, temporal tables, JSON, spatial types), lowers them
to a DataFusion LogicalPlan IR, applies energy-aware optimization rules,
and generates DuckDB-dialect SQL.

The project includes a 50-operation benchmark suite that exercises
MSSQL-unique features and verifies that DuckDB produces identical result
sets (MD5 hash comparison against a gold standard captured from MSSQL).

### Pipeline

```
MSSQL T-SQL → [parser] → AST → [ir] → LogicalPlan → [optimizer] → [codemodel] → DuckDB SQL
```

1. **parser** — MSSQL T-SQL to AST using `sqlparser-rs` (MSSQL dialect)
2. **ir** — AST to DataFusion `LogicalPlan` (engine-agnostic relational algebra)
3. **optimizer** — `LogicalPlan` to optimized `LogicalPlan` (energy-aware rewrite rules)
4. **codemodel** — optimized `LogicalPlan` to DuckDB SQL string
5. **catalog** — logical MSSQL schema to physical DuckDB schema mapping (multiple variants)

---

## Quick Start

### Prerequisites

- [Rust](https://rustup.rs) (stable, 1.75+)
- [Docker](https://www.docker.com/products/docker-desktop) (for MSSQL source database)

### Build

```bash
cargo build --release
```

### Translate a single T-SQL statement

```bash
# From stdin
echo "SELECT TOP 10 * FROM Employees" | ./target/release/datamigrata translate

# From file
./target/release/datamigrata translate --input mssql.sql --output duckdb.sql
```

### Generate DDL for a schema variant

```bash
./target/release/datamigrata ddl --variant baseline
./target/release/datamigrata ddl --variant columnar
./target/release/datamigrata ddl --variant precomputed
```

---

## CLI Reference

| Command | Description |
|---------|-------------|
| `translate` | Translate MSSQL T-SQL to DuckDB SQL |
| `ddl` | Generate DDL for a schema variant |
| `generate-ops` | Generate the 50 canonical DuckDB SQL op files |
| `apply-fixes` | Apply corrected op translations (35 ops) |
| `verify` | Verify ops against gold standard (MD5 comparison) |
| `verify-all-variants` | Verify all 3 schema variants |
| `capture-gold` | Capture gold standard CSVs from MSSQL (v1) |
| `capture-gold-v2` | Capture gold standard CSVs from MSSQL (v2, with SET prefix) |
| `search` | Combinatorial energy optimization search (hardcoded estimates) |
| `search-wave6` | DuckDB execution-based energy search |
| `build-duckdb` | Build DuckDB database from CSV files (hardcoded DDL) |
| `build-duckdb-v3` | Build DuckDB from schema.json (datetime2 as VARCHAR) |
| `build-views` | Create views and macros in DuckDB |
| `build-variants` | Build 3 schema variant databases |
| `export-mssql` | Export MSSQL tables to CSV via docker exec sqlcmd |
| `apply-op41-fix` | Apply op41 SensitiveData fix to all variant DBs |

---

## The 50-Operation Benchmark

The benchmark suite exercises MSSQL-unique features across 9 categories.
Each op is translated to DuckDB SQL and verified against a gold standard
captured from MSSQL.

| Category | Ops | MSSQL-Unique Highlights |
|----------|-----|------------------------|
| Hierarchical & Recursive | 1-5 | `HIERARCHYID`, `MAXRECURSION` |
| XML Native | 6-10 | XML DML `modify()`, XML indexes |
| JSON Native | 11-15 | `JSON_MODIFY`, `FOR JSON` nested |
| Temporal Tables | 16-20 | `AS OF` / `BETWEEN` / `CONTAINED IN` |
| Advanced Views | 21-30 | Indexed views, `INSTEAD OF` triggers |
| Spatial Data | 31-35 | Geography ellipsoidal distances |
| Columnstore & In-Memory | 36-40 | Natively compiled procedures |
| Security & Encryption | 41-45 | RLS, Dynamic Masking, Audit |
| Advanced Programmability | 46-50 | TVPs, `MERGE OUTPUT`, `CHANGETABLE` |

### Energy Model

```
cpu_joules   = cpu_ms * 5 / 1000
dram_joules  = logical_reads * 8192 * 12.5e-9
total_joules = cpu_joules + dram_joules
```

The search harness tests 3 schema variants (baseline, columnar,
precomputed) with 3 rewrite alternatives per op, selecting the
energy-optimal configuration via greedy per-op selection.

---

## Database Schema

| Schema | Table | Rows | Key Features |
|--------|-------|------|-------------|
| **HR** | `Employees` | 5,000 | Hierarchy, XML, Computed, RowVersion |
| **HR** | `OrgChart` | ~100 | `HIERARCHYID` native type |
| **Sales** | `Products` | 1,000 | Full-text, Persisted computed |
| **Sales** | `Transactions` | 5,000 | Temporal, JSON, Geography |
| **Sales** | `TransactionsHistory` | varies | Auto-managed by temporal |
| **Sales** | `CustomerCache` | 2,000 | Memory-optimized (Hekaton) |
| **Sales** | `HighSpeedLookup` | 1,000 | Memory-optimized + Hash index |
| **Sales** | `PartitionedSales` | 2,000 | Partitioned by year |
| **Audit** | `EventLog` | 1,000 | Sequence-driven PK |
| **Security** | `SensitiveData` | 100 | Encrypted (cert + symmetric key) |
| **Archive** | `OldTransactions` | 3,000 | For partitioned views |
| **Staging** | `ETLSource` | 500 | For MERGE/ETL demos |

---

## Repository Structure

```
DataMigrata/
├── Cargo.toml                         # Rust project manifest
├── src/
│   ├── main.rs                        # CLI entry point
│   ├── lib.rs                         # Library root
│   ├── parser/                        # MSSQL T-SQL parser (sqlparser-rs)
│   ├── ir/                            # AST to LogicalPlan lowering
│   ├── optimizer/                     # Energy-aware rewrite rules
│   ├── codemodel/                     # LogicalPlan to DuckDB SQL
│   ├── catalog/                       # Schema variant mapping
│   ├── protocol/                      # TDS/TNS protocol stubs
│   ├── tds_server/                    # TDS server stub
│   └── tools/                         # Rust tooling (replaces Python scripts)
│       ├── common/                    # Shared modules (sql_translate, value_fmt, etc.)
│       ├── gen/                        # SQL generation (generate_ops, gen_spatial_ops)
│       ├── verify/                    # Verification (verify_ops, capture_gold)
│       ├── search/                    # Search/optimization (search_harness)
│       ├── build/                     # Export/build (build_duckdb, export_mssql)
│       ├── fixes/                     # Fix scripts (fix_ops, fix_op41)
│       └── tooling/                   # Codespace tooling (deprecated)
├── tests/
│   ├── operations_50.rs               # 50-operation integration tests
│   └── tools_integration.rs           # DuckDB + value formatting tests
├── sql/
│   ├── 00_COMPLETE_MSSQL_Deployment.sql  # Idempotent DB + ~20K rows
│   ├── 00_SCHEMA_ONLY_Deployment.sql     # Schema only, no data
│   ├── 01_MSSQL_Migration_SyntheticData.sql
│   ├── 01_MSSQL_Populate_Data_SetBased.sql
│   ├── 02_MSSQL_50_Operations_Expanded.sql       # 50 sophisticated operations
│   └── 02_MSSQL_50_Sophisticated_Operations.sql  # Original lightweight ops
├── docker/
│   └── docker-compose.yml              # MSSQL 2022 Developer container
├── docs/
│   ├── PROJECT_PLAN.md                # Architecture & roadmap
│   ├── SPECIFICATION_DRAFT_v02.md     # Current specification
│   └── TECHNOLOGY_KNOWLEDGE_BASE.md   # Technology reference
├── scripts/                           # Legacy Python scripts (reference only)
├── best_config/                      # Optimized op SQL files
├── gold_standard/                     # MSSQL gold-standard CSVs
├── duckdb_migrated/                   # DuckDB SQL translations + database
└── mssql_data/                        # Exported MSSQL CSV data
```

---

## Codespace Operations

This repo ships a [`CODESPACE.yaml`](CODESPACE.yaml) manifest for
[`codespacectl`](https://github.com/topic-hash/codespacectl) — a Rust CLI
that lets AI agents drive GitHub Codespaces reliably.

### One-time setup

```bash
# Install codespacectl
curl -L https://github.com/topic-hash/codespacectl/releases/latest/download/codespacectl-linux-amd64 \
  -o /usr/local/bin/codespacectl && chmod +x $_

# Set your GitHub PAT (fine-grained, codespace scope)
export CODESPACECTL_TOKEN=ghp_xxx
```

### Workflow

```bash
codespacectl --manifest ./CODESPACE.yaml connect --codespace <name>
codespacectl exec build         # cargo build --release
codespacectl exec test          # cargo test
codespacectl exec clippy        # cargo clippy -- -D warnings
codespacectl exec fmt-check     # cargo fmt --check
codespacectl exec docker-up     # docker compose up -d
codespacectl exec deploy-sql    # ~2 minutes, deploys 20K rows
codespacectl exec run-50-ops    # 50 sophisticated MSSQL operations
codespacectl stop
```

---

## Testing

```bash
# Unit tests (52 tests)
cargo test --lib

# Integration tests (DuckDB connection, value formatting)
cargo test --test tools_integration

# 50-operation benchmark tests
cargo test --test operations_50
```

---

## License

Apache 2.0. See [LICENSE](LICENSE) for details.
