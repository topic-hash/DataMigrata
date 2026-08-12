# DataMigrata

> **Intelligent Oracle-to-MSSQL Semantic Translation Middleware**
>
> A universal translation and optimization bridge that autonomously restructures relational data estates into the most efficient MSSQL format possible — while maintaining absolute compatibility with existing Oracle application logic.

---

## Codespace Operations (agent-driven via `codespacectl`)

This repo ships a [`CODESPACE.yaml`](CODESPACE.yaml) manifest for
[`codespacectl`](https://github.com/topic-hash/codespacectl) — a single-binary
Rust CLI that lets AI agents drive GitHub Codespaces reliably.

### One-time setup

```bash
# Install codespacectl
curl -L https://github.com/topic-hash/codespacectl/releases/latest/download/codespacectl-linux-amd64 \
  -o /usr/local/bin/codespacectl && chmod +x $_

# Set your GitHub PAT (fine-grained, `codespace` scope)
export CODESPACECTL_TOKEN=ghp_xxx

# Tell codespacectl where the vendored gh binary lives (codespacectl ships one too,
# but if you're running from a clone of DataMigrata, use the one in tools/bin/)
export CODESPACECTL_GH_BIN=/path/to/codespacectl/tools/bin/gh
```

### Workflow

```bash
codespacectl --manifest ./CODESPACE.yaml connect --codespace <name>
codespacectl exec build         # cargo build --release
codespacectl exec test          # cargo test --test operations_50
codespacectl exec bench         # cargo bench
codespacectl exec clippy        # cargo clippy -- -D warnings
codespacectl exec fmt-check     # cargo fmt --check
codespacectl exec docker-up     # docker compose up -d
codespacectl exec deploy-sql    # ~2 minutes, deploys 20K rows
codespacectl exec run-50-ops     # 50 sophisticated MSSQL operations
codespacectl stop
```

All commands support `--json` for structured output. See
[the codespacectl docs](https://github.com/topic-hash/codespacectl/blob/main/docs/CLI_REFERENCE.md)
for the full envelope schema.

The legacy Python tooling (`tools/codespace_ssh.py`, `tools/setup.py`,
`AGENT_CODESPACE_PROMPT.md`) is preserved for backward compatibility but
should be considered deprecated — `codespacectl` replaces it.

---

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop) (free)
- [Visual Studio Code](https://code.visualstudio.com/download) + [MSSQL Extension](https://aka.ms/vscode-mssql)
- SQL Server 2022 Developer Edition (free via Docker)

### 1. Start the Database

```bash
cd docker
docker-compose up -d
```

Wait 30 seconds for initialization.

### 2. Connect in VS Code

- Press `F1` → **MS SQL: Manage Connection Profile**
- Server: `localhost,1433`
- Authentication: SQL Login
- Username: `sa`
- Password: `YourStrong@Passw0rd`

### 3. Deploy the Database

Open `sql/00_COMPLETE_MSSQL_Deployment.sql` → Execute (`Ctrl+Shift+E`)

### 4. Run the 50 Operations

Open `sql/02_MSSQL_50_Operations_Expanded.sql` → Execute category by category.

---

## Repository Structure

```
DataMigrata/
├── README.md                           # This file
├── docs/
│   └── PROJECT_PLAN.md                 # Middleware architecture & roadmap
├── sql/
│   ├── 00_COMPLETE_MSSQL_Deployment.sql          # Idempotent DB + ~20K rows
│   ├── 02_MSSQL_50_Operations_Expanded.sql       # 50 sophisticated operations
│   ├── 01_MSSQL_Migration_SyntheticData.sql      # Original lightweight version
│   └── 02_MSSQL_50_Sophisticated_Operations.sql  # Original lightweight ops
└── docker/
    └── docker-compose.yml              # One-command MSSQL container
```

---

## Database Overview

| Schema | Table | Rows | Key Features |
|--------|-------|------|-------------|
| **HR** | `Employees` | 5,000 | Hierarchy, XML, Computed, RowVersion |
| **HR** | `OrgChart` | ~100 | `HIERARCHYID` native type |
| **Sales** | `Products` | 1,000 | Full-text, Persisted computed |
| **Sales** | `Transactions` | 5,000 | **Temporal**, JSON, Geography |
| **Sales** | `TransactionsHistory` | varies | Auto-managed by temporal |
| **Sales** | `CustomerCache` | 2,000 | **Memory-optimized** (Hekaton) |
| **Sales** | `HighSpeedLookup` | 1,000 | Memory-optimized + Hash index |
| **Sales** | `PartitionedSales` | 2,000 | Partitioned by year |
| **Audit** | `EventLog` | 1,000 | Sequence-driven PK |
| **Security** | `SensitiveData` | 100 | Encrypted (cert + symmetric key) |
| **Archive** | `OldTransactions` | 3,000 | For partitioned views |
| **Staging** | `ETLSource` | 500 | For MERGE/ETL demos |

---

## The 50 Operations

| Cat | Ops | Category | MSSQL-Unique Highlights |
|-----|-----|----------|------------------------|
| 1 | 1-5 | Hierarchical & Recursive | `HIERARCHYID`, `MAXRECURSION` |
| 2 | 6-10 | XML Native | XML DML `modify()`, XML indexes |
| 3 | 11-15 | JSON Native | `JSON_MODIFY`, `FOR JSON` nested |
| 4 | 16-20 | Temporal Tables | `AS OF` / `BETWEEN` / `CONTAINED IN` |
| 5 | 21-30 | Advanced Views | Indexed views, `INSTEAD OF` triggers |
| 6 | 31-35 | Spatial Data | Geography ellipsoidal distances |
| 7 | 36-40 | Columnstore & In-Memory | Natively compiled procedures |
| 8 | 41-45 | Security & Encryption | RLS, Dynamic Masking, Audit |
| 9 | 46-50 | Advanced Programmability | TVPs, `MERGE OUTPUT`, `CHANGETABLE` |

---

## Oracle → MSSQL Feature Mapping

| Oracle Feature | MSSQL Equivalent | Notes |
|----------------|-----------------|-------|
| `CONNECT BY` | Recursive CTE + `HIERARCHYID` | `HIERARCHYID` is MSSQL-only |
| `XMLType` | `XML` + XML indexes + XML DML | XML DML `modify()` is MSSQL-only |
| JSON (12c+) | JSON functions + `FOR JSON` + `OPENJSON` | MSSQL JSON is more mature |
| Flashback Query | Temporal tables (`FOR SYSTEM_TIME`) | Declarative, ANSI standard |
| Materialized Views | Indexed views (`SCHEMABINDING`) | Auto-maintained |
| Virtual Private DB | Row-Level Security | Inline TVF predicates |
| Data Redaction | Dynamic Data Masking | Built-in functions |
| `SDO_GEOMETRY` | Geography/Geometry types | Full OGC compliance |
| Partitioning | Partition functions + schemes | Range/List/Hash |
| PL/SQL packages | Stored procedures + CLR | CLR = .NET integration |
| Advanced Queuing | Service Broker | Native messaging |
| TDE | TDE / Always Encrypted | Column-level encryption |
| Fine-Grained Auditing | SQL Server Audit Specifications | Server + Database level |
| Flashback Data Archive | Temporal + history retention | Automatic |
| `DBMS_CRYPTO` | Symmetric keys + certificates | SMK→DMK→Cert→Key |
| `VARRAY`/`TABLE` | User-defined table types | Table-valued parameters |
| Autonomous transactions | In-memory OLTP + natively compiled | Lock-free, latch-free |
| Parallel Query | Batch mode + parallel query | Columnstore batch mode |
| Bitmap indexes | Columnstore indexes | In Standard Edition |

---

## Why MSSQL Over Oracle for Cost Reduction

| Factor | Oracle | MSSQL |
|--------|--------|-------|
| Developer Edition | XE (severely limited) | **Full-featured, FREE** |
| Temporal Tables | Complex flashback setup | **Declarative** |
| Columnstore | Requires Enterprise + In-Memory license | **Standard Edition** |
| In-Memory OLTP | Separately licensed option | **Included** |
| JSON Support | `JSON_EXISTS`/`JSON_VALUE` limitations | **First-class** |

---

## Tooling

- **VS Code** + **MSSQL Extension** (actively maintained, replaces retired Azure Data Studio)
- **SSMS** (Windows-only alternative)
- **Docker** for containerized local development

---
## License: 
Apache 2.0 (effective from 2026-07-26). Previously MIT.
