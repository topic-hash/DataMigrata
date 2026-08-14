```markdown
# DataMigrata

> **Intelligent MSSQL-to-DuckDB Semantic Translation Middleware**

A **real-time semantic translation layer** that enables existing **MSSQL-speaking applications** to seamlessly interact with **DuckDB** without any changes to business logic or interfaces. DataMigrata acts as a **drop-in replacement** for MSSQL, intercepting T-SQL queries, translating them through a **compiler-based pipeline** (parsing, abstract syntax tree construction, intermediate representation optimization, and DuckDB-SQL code generation), and executing them against a DuckDB target.

---

## Quick Start

### Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop) (for local MSSQL instance)
- [DuckDB](https://duckdb.org/) (embedded, no setup required)
- Rust toolchain (for building the middleware)

### 1. Start MSSQL Database
```bash
cd docker
docker-compose up -d
```
Wait 30 seconds for initialization.

### 2. Connect to MSSQL
- **Server**: `localhost,1433`
- **Authentication**: SQL Login
- **Username**: `sa`
- **Password**: `YourStrong@Passw0rd`

### 3. Deploy the MSSQL Database
Open `sql/00_COMPLETE_MSSQL_Deployment.sql` in your SQL client and execute it to create the schema and populate with ~20,000 rows.

### 4. Run the 50 MSSQL Operations
Open `sql/02_MSSQL_50_Operations_Expanded.sql` and execute the operations category by category.

---

## Repository Structure

```
DataMigrata/
├── README.md                          # This file
├── CODESPACE.yaml                    # Agent-driven workflow manifest
├── docs/
│   └── PROJECT_PLAN.md                # Middleware architecture & roadmap
├── sql/
│   ├── 00_COMPLETE_MSSQL_Deployment.sql       # Idempotent DB + ~20K rows
│   ├── 01_MSSQL_Migration_SyntheticData.sql   # Lightweight test data
│   ├── 02_MSSQL_50_Operations_Expanded.sql    # 50 sophisticated MSSQL operations
│   └── duckdb_migrated/               # Translated DuckDB operations
├── src/
│   └── middleware/                    # Rust-based middleware implementation
└── docker/
    └── docker-compose.yml             # MSSQL container configuration
```

---

## Database Overview

The test database includes 12 tables across multiple schemas, showcasing **enterprise MSSQL features** that need to be handled during migration to DuckDB:

| Schema      | Table                | Rows   | Key Features                          |
|-------------|----------------------|--------|---------------------------------------|
| **HR**      | `Employees`           | 5,000  | Hierarchy, XML, Computed Columns        |
| **HR**      | `OrgChart`            | ~100   | `HIERARCHYID` native type              |
| **Sales**   | `Products`            | 1,000  | Full-text search, Persisted computed   |
| **Sales**   | `Transactions`        | 5,000  | Temporal tables, JSON, Geography       |
| **Sales**   | `TransactionsHistory` | varies | Auto-managed by temporal tables       |
| **Sales**   | `CustomerCache`       | 2,000  | Memory-optimized (Hekaton)             |
| **Sales**   | `HighSpeedLookup`     | 1,000  | Memory-optimized + Hash index          |
| **Sales**   | `PartitionedSales`    | 2,000  | Partitioned by year                   |
| **Audit**   | `EventLog`            | 1,000  | Sequence-driven PK                    |
| **Security**| `SensitiveData`       | 100    | Encrypted (cert + symmetric key)      |
| **Archive** | `OldTransactions`     | 3,000  | For partitioned views                  |
| **Staging** | `ETLSource`           | 500    | For MERGE/ETL demos                    |

---

## The 50 MSSQL Operations

The 50 operations cover **all major MSSQL features** and are organized by category. **27 of these operations** represent feature gaps in DuckDB that require **compiler-based translation**.

| Category                     | Operations | MSSQL-Unique Highlights                          |
|------------------------------|-------------|--------------------------------------------------|
| **Hierarchical & Recursive** | 1-5         | `HIERARCHYID`, `MAXRECURSION`                      |
| **XML Native**               | 6-10        | XML DML `modify()`, XML indexes                   |
| **JSON Native**              | 11-15       | `JSON_MODIFY`, `FOR JSON` nested                  |
| **Temporal Tables**          | 16-20       | `AS OF` / `BETWEEN` / `CONTAINED IN`               |
| **Advanced Views**            | 21-30       | Indexed views, `INSTEAD OF` triggers               |
| **Spatial Data**              | 31-35       | Geography ellipsoidal distances                 |
| **Columnstore & In-Memory**   | 36-40       | Natively compiled procedures                     |
| **Security & Encryption**     | 41-45       | Row-Level Security, Dynamic Masking, Audit       |
| **Advanced Programmability**  | 46-50       | Table-Valued Parameters, `MERGE OUTPUT`, `CHANGETABLE` |

---

## Architecture

### Compiler Pipeline
DataMigrata uses a **multi-stage compiler pipeline** to translate T-SQL to DuckDB-SQL:

1. **Parsing**: T-SQL queries are parsed into an **Abstract Syntax Tree (AST)**
2. **Intermediate Representation (IR)**: The AST is converted to an optimized IR that abstracts MSSQL-specific syntax
3. **Optimization**: DuckDB-specific optimizations are applied (e.g., predicate pushdown, join simplification)
4. **Code Generation**: The IR is translated to **DuckDB-SQL**

### Agentic Coding Approach
The system incorporates **autonomous agents** that:
- **Analyze** T-SQL patterns and identify feature gaps
- **Generate** automatic workarounds for unsupported DuckDB features (e.g., `TRY-CATCH` -> error handling in middleware)
- **Optimize** translations based on query patterns and performance metrics
- **Validate** translations against MSSQL results to ensure semantic equivalence

### Protocol Emulation
- **TDS Protocol Layer**: The middleware emulates MSSQL's Tabular Data Stream (TDS) protocol to maintain compatibility with existing applications
- **Session State Management**: Handles variables, temporary tables, and transactions
- **Result Transformation**: Converts DuckDB results to TDS-compatible format

---

## MSSQL-to-DuckDB Feature Mapping

| MSSQL Feature               | DuckDB Equivalent/Workaround          | Status          | Notes                                  |
|-----------------------------|---------------------------------------|-----------------|----------------------------------------|
| `IDENTITY`                  | `AUTOINCREMENT`                       | Native          |                                        |
| `HIERARCHYID`               | Custom type/JSON                      | Translation     | Requires compiler transformation         |
| `XML` DML                   | JSON functions                        | Translation     | XML to JSON conversion                   |
| Temporal Tables             | Custom temporal logic                 | Translation     | Emulated via triggers                  |
| `TRY-CATCH`                 | Middleware error handling            | Translation     | Handled at middleware level            |
| `MERGE`                     | `INSERT`/`UPDATE`/`DELETE` sequence    | Translation     | Decomposed by compiler                 |
| `OUTPUT` Clause             | `RETURNING` clause                    | Translation     | DuckDB's RETURNING as alternative       |
| Row-Level Security          | Custom filtering logic                | Translation     | Implemented in middleware               |
| Memory-Optimized Tables     | Standard tables                       | Native          | DuckDB's in-memory nature              |
| Full-Text Search            | DuckDB FTS extension                  | Native          |                                        |
| Geography/Geometry Types    | DuckDB spatial extension             | Native          |                                        |
| `SEQUENCE`                  | DuckDB sequences                      | Native          |                                        |

---

## Why MSSQL to DuckDB?

### Performance & Efficiency
| Factor                     | MSSQL                          | DuckDB                          | Benefit                          |
|----------------------------|--------------------------------|---------------------------------|----------------------------------|
| **Query Execution**        | General-purpose RDBMS          | Columnar, in-process            | Faster analytical queries        |
| **Resource Usage**         | Heavy (server process)         | Lightweight (embedded)          | Lower memory/CPU footprint       |
| **Deployment**             | Server-based                   | Embedded/No server              | Simpler deployment              |
| **Cost**                   | Licensing costs                | Free & Open Source              | Significant cost reduction      |
| **Embeddability**          | Requires separate server       | In-process library              | Direct integration possible     |

### Energy Efficiency
Measured energy profiles show **DuckDB consumes significantly less energy** for equivalent operations, making it ideal for **sustainable computing** initiatives.

---

## Codespace Operations (Agent-Driven via `codespacectl`)

This repository includes a [`CODESPACE.yaml`](CODESPACE.yaml) manifest for [`codespacectl`](https://github.com/topic-hash/codespacectl), enabling AI agents to drive GitHub Codespaces reliably.

### One-Time Setup
```bash
# Install codespacectl
curl -L https://github.com/topic-hash/codespacectl/releases/latest/download/codespacectl-linux-amd64 \
  -o /usr/local/bin/codespacectl && chmod +x $_

# Set your GitHub PAT (fine-grained, `codespace` scope)
export CODESPACECTL_TOKEN=ghp_xxx

# Configure gh binary path
export CODESPACECTL_GH_BIN=/path/to/codespacectl/tools/bin/gh
```

### Workflow Commands
```bash
codespacectl --manifest ./CODESPACE.yaml connect --codespace <name>
codespacectl exec build         # cargo build --release
codespacectl exec test          # cargo test --test operations_50
codespacectl exec bench         # cargo bench
codespacectl exec clippy        # cargo clippy -- -D warnings
codespacectl exec fmt-check     # cargo fmt --check
codespacectl exec docker-up     # docker compose up -d
codespacectl exec deploy-sql    # Deploy ~20K rows (~2 minutes)
codespacectl exec run-50-ops     # Execute 50 MSSQL operations
codespacectl stop
```
All commands support `--json` for structured output.

---
## Tooling
- **VS Code** + **MSSQL Extension** (for MSSQL development)
- **DuckDB CLI** (for DuckDB testing)
- **Docker** (for containerized MSSQL instance)
- **Rust** (for middleware development)

---
## License
Apache 2.0 (effective from 2026-07-26).
```
