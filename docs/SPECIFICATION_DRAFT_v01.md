# DataMigrata Middleware Specification

## 1. Vision and Scope

### 1.1 What This Middleware Does

DataMigrata is an intelligent database migration middleware that sits between an existing Oracle-compatible application and a Microsoft SQL Server target. Unlike conventional ETL tools, schema migration utilities, or "lift and shift" database porting approaches, DataMigrata does not simply copy data from one relational database to another. Instead, it acts as a real-time semantic translation layer: the existing application continues to issue Oracle SQL and PL/SQL as if it were connected to a native Oracle instance, while the middleware intercepts those queries, translates them through a compiler-based pipeline (parsing, abstract syntax tree construction, intermediate representation optimization, and T-SQL code generation), and executes them against an MSSQL target that stores data in an optimized representation that is structurally different from the Oracle source.

The middleware is the "Zwischenabbildung" -- the intermediate layer. It is the bridge that decouples the application from the database engine while preserving full compatibility. The primary value proposition is performance and cost: by restructuring data into the most efficient MSSQL-native format (HIERARCHYID columns instead of adjacency lists, temporal tables instead of flashback logs, columnstore indexes instead of bitmap indexes, memory-optimized tables instead of disk-based tables for hot paths), the middleware enables the target system to execute queries faster and cheaper than the source Oracle instance ever could.

### 1.2 Problem Statement

Organizations running Oracle database workloads face a persistent cost and performance problem. Oracle licensing is expensive at scale, and the proprietary Oracle platform creates vendor lock-in that limits architectural flexibility. Meanwhile, Microsoft SQL Server offers a rich set of advanced features -- many of which are included in the free Developer Edition -- that can match or exceed Oracle capabilities for specific workloads. The challenge is that existing applications are built against Oracle-specific SQL dialects, PL/SQL stored procedures, and Oracle data types. Rewriting these applications is prohibitively expensive and risky.

The existing landscape of migration tools (Ora2Pg, AWS Schema Conversion Tool, Microsoft's own SSMA) focuses on one-time schema and data migration. They convert Oracle DDL to T-SQL, move data, and hand the application a new connection string. This approach fails in practice because Oracle SQL is not T-SQL: the syntax differs, the data types differ, the behavioral semantics differ, and the stored procedures differ. Applications break. Post-migration debugging is expensive. The ERP migration post-mortems from Birmingham (2020, 100M GBP failure), Revlon (supply chain collapse), Lidl (project abandonment after years), and others demonstrate the catastrophic risk of naive migration approaches.

DataMigrata solves this by not asking the application to change at all. The application continues to speak Oracle SQL over the TNS wire protocol. The middleware translates at runtime.

### 1.3 How This Differs From Simple ETL and Migration Tools

Conventional migration tools operate in batch mode: extract data from Oracle, transform to MSSQL-compatible format, load into MSSQL, and redirect the application. The data structures on MSSQL mirror the Oracle structures (perhaps with type conversions). This is fundamentally a 1:1 copy approach.

DataMigrata takes a fundamentally different approach. It operates as a live proxy middleware that is always running between the application and the target. The data on the MSSQL target is stored in an optimized representation that is deliberately different from the Oracle source structure. This optimization is possible because the middleware understands the semantic intent of the data, not just its physical layout.

For example, an Oracle table with a CONNECT BY hierarchy using a parent-child adjacency list (ManagerID referencing EmployeeID) would, in a simple migration, become an identical MSSQL table with the same adjacency list. DataMigrata instead stores this data using MSSQL's native HIERARCHYID data type, which enables subtree queries in constant time rather than recursive joins. When the application issues a CONNECT BY query, the middleware translates it to an equivalent HIERARCHYID operation against the optimized target. The result is returned in the Oracle format the application expects.

This distinction -- optimized storage with semantic back-transformation -- is the core architectural innovation of DataMigrata.

### 1.4 The Live Translation Paradigm

The application believes it is talking to an Oracle database. It uses the standard Oracle database driver (JDBC thin driver, OCI, or ODP.NET configured for Oracle), connects over the TNS wire protocol, and issues standard Oracle SQL and PL/SQL. The middleware intercepts this traffic at the protocol level, parses the incoming SQL into an abstract syntax tree (AST), lowers the AST into Apache Calcite's relational algebra intermediate representation (IR), optimizes the IR for MSSQL target execution, generates T-SQL, and executes it against the MSSQL instance. The results are then formatted back into the Oracle wire protocol format and returned to the application.

This means:
- The application binary requires zero changes.
- The application's Oracle driver requires zero changes.
- The middleware is stateful: it manages sessions, transactions, isolation levels, and connection state.
- Queries are translated at runtime, not pre-migrated.
- Data is stored on the target in the most performant format MSSQL supports.

### 1.5 Object Storage (MinIO) for Unstructured and Semi-Structured Data

Real enterprise data estates are not purely relational. XML documents, JSON payloads, LOB (Large Object) data, audit logs, and binary files must also be managed. DataMigrata integrates MinIO -- a high-performance, S3-compatible object storage server that runs on-premises -- as the blob store for unstructured data.

Why MinIO and not AWS S3? Because the middleware is designed for on-premises and hybrid deployments. Organizations migrating from Oracle to MSSQL are often doing so to maintain control over their data infrastructure. Sending LOB data to AWS introduces latency, egress costs, and regulatory complexity. MinIO provides the same S3 API locally, with no network egress costs and full data sovereignty.

The middleware decides what goes into MSSQL relational storage and what goes into MinIO object storage based on data classification rules:
- Structured relational data: stored in MSSQL tables in optimized format.
- XML/JSON documents above a size threshold: stored in MinIO with metadata references in MSSQL.
- LOB columns (BLOB, CLOB, NCLOB): stored in MinIO with pointer columns in MSSQL.
- Audit logs and event histories: stored in MinIO for long-term retention, with summary tables in MSSQL.

### 1.6 Dual-Direction Data Flow

DataMigrata manages bidirectional data transformation:

**Write path (Oracle format in, MSSQL optimized):** When the application issues an INSERT, UPDATE, or DELETE, the middleware receives the Oracle-formatted statement, translates it to T-SQL, and executes it against the MSSQL target. The data is physically stored in the optimized MSSQL representation. For example, an INSERT with a CONNECT BY-compatible hierarchy structure is translated to store data using HIERARCHYID format on the target.

**Read path (MSSQL optimized, Oracle format out):** When the application issues a SELECT, the middleware translates the Oracle SQL to T-SQL, executes against the optimized MSSQL representation, and then transforms the result set back to the format the Oracle application expects. For example, a query that returns HIERARCHYID path data is reformatted to present the same result set structure that Oracle's CONNECT BY would produce, including columns like LEVEL and PRIOR.

This bidirectional transformation is the critical differentiator. It is what makes the middleware more than a simple query translator: it maintains a semantic mapping between the source format and the target format that is invisible to the application.

---

## 2. Architecture Overview

### 2.1 System Architecture

The traditional database architecture follows a straightforward path:

```
Traditional Architecture:
+-------------+     +------------------+     +------------------+
|  Application |---->| Database Driver  |---->| Source Database   |
|  (Oracle SQL)|     |  (Oracle JDBC)   |     |  (Oracle RDBMS)  |
+-------------+     +------------------+     +------------------+
```

DataMigrata inserts itself into this flow as a stateful middleware layer:

```
DataMigrata Architecture:
+-------------+     +------------------+     +------------------+     +--------------------+     +------------------+
|  Application |---->| Custom DB Driver |---->|   DataMigrata    |---->| MSSQL Driver       |---->| Optimized Target  |
|  (Oracle SQL)|     | (TNS-speaking)   |     |   Middleware     |     | (tedious/mssql)    |     | (MSSQL 2022 Dev)  |
+-------------+     +------------------+     |                  |     +--------------------+     +------------------+
                                            |  - TNS Parser    |                                  |
                                            |  - SQL Parser    |                                  |
                                            |  - Calcite IR    |     +------------------+
                                            |  - T-SQL Gen     |---->| MinIO Instance    |
                                            |  - Session Mgmt  |     | (Object Storage)  |
                                            |  - Back-Transform|     +------------------+
                                            +------------------+
```

Key architectural characteristics:

1. **Stateful middleware, not stateless proxy.** The middleware maintains session state including active transactions, isolation levels, temporary tables, session context variables (SESSION_CONTEXT equivalent), and prepared statement caches. This is fundamentally different from a simple SQL proxy that would forward queries without understanding them.

2. **Custom database driver.** The application connects to the middleware using a driver that speaks the TNS wire protocol. This can be implemented as a thin wrapper around the standard Oracle JDBC/ODP.NET driver that redirects the connection from a real Oracle listener to the middleware's TNS-speaking endpoint. Alternatively, the middleware itself can implement a minimal TNS server that accepts connections from unmodified Oracle drivers.

3. **Compiler-based query pipeline.** Every SQL statement passes through four phases: parsing (Oracle SQL to AST), IR lowering (AST to Apache Calcite RelNode tree), optimization (predicate pushdown, join reordering, semantic conversion), and code generation (RelNode tree to T-SQL).

4. **MinIO integration.** The middleware routes blob data to MinIO and maintains reference metadata in MSSQL, implementing a polyglot persistence strategy.

### 2.2 The Compiler Pipeline

The query translation pipeline is the intellectual core of DataMigrata. It is modeled on the principles described in the "Beyond the Black Box" analysis document, which advocates for a compiler-based approach to database migration.

```
Oracle SQL / PL-SQL
        |
        v
+-------------------+
| Phase 1: Parsing  |   Parse Oracle SQL into Abstract Syntax Tree (AST)
|                   |   - TNS protocol intercept
|                   |   - Tokenize Oracle SQL dialect
|                   |   - Handle Oracle-specific syntax:
|                   |     CONNECT BY, PRIOR, ROWNUM, DECODE,
|                   |     NVL, (+) outer joins, DUAL,
|                   |     PL/SQL blocks, package calls
+-------------------+
        |
        v
    AST (Oracle-specific)
        |
        v
+-------------------+
| Phase 2: IR        |   Lower AST to Apache Calcite RelNode tree
|                   |   - Convert Oracle AST to Calcite SQL nodes
|                   |   - Map Oracle data types to Calcite logical types
|                   |   - Normalize semantic differences
|                   |   - Convert Oracle catalog references to MSSQL catalog
+-------------------+
        |
        v
    RelNode Tree (database-agnostic IR)
        |
        v
+-------------------+
| Phase 3:          |   Optimize for MSSQL target execution
| Optimization      |   - Predicate pushdown for MSSQL indexes
|                   |   - Join reordering for MSSQL optimizer
|                   |   - Source-to-target semantic conversion:
|                   |     CONNECT BY -> HIERARCHYID or recursive CTE
|                   |     ROWNUM -> TOP / OFFSET-FETCH
|                   |     DECODE -> CASE WHEN
|                   |     NVL -> ISNULL / COALESCE
|                   |     VPD predicates -> RLS functions
|                   |     XMLType operations -> XML native type
|                   |     SDO_GEOMETRY -> Geography/Geometry
|                   |   - Index selection hints for columnstore/spatial
+-------------------+
        |
        v
    Optimized RelNode Tree (MSSQL-targeted)
        |
        v
+-------------------+
| Phase 4: Code     |   Generate T-SQL for MSSQL execution
| Generation        |   - RelNode tree -> syntactically valid T-SQL
|                   |   - Handle MSSQL-specific syntax:
|                   |     HIERARCHYID methods, FOR SYSTEM_TIME,
|                   |     JSON_MODIFY, XML DML modify(),
|                   |     MERGE with OUTPUT, OPENJSON
|                   |   - Parameter binding from Oracle to MSSQL format
|                   |   - Execute via MSSQL driver (tedious or mssql npm)
+-------------------+
        |
        v
    T-SQL (MSSQL-compatible)
```

**Phase 1 -- Parsing:** The middleware receives raw SQL text from the application (over TNS protocol). It tokenizes this text into an AST using a parser that understands Oracle SQL dialect. This includes Oracle-specific constructs that are not part of the SQL standard: CONNECT BY with PRIOR for hierarchical queries, ROWNUM for row limiting, DECODE for conditional expressions, the (+) syntax for outer joins, NVL for null handling, DUAL for dual-table selects, and the full PL/SQL block syntax for procedural code. The parser must be able to distinguish between SQL statements and PL/SQL blocks (which may contain BEGIN...END blocks with variable declarations, loops, cursors, exception handlers, and procedure calls).

**Phase 2 -- IR (Apache Calcite):** Apache Calcite serves as the intermediate representation engine. Calcite parses multiple SQL dialects into a canonical relational algebra representation (the RelNode tree). The middleware uses Calcite's OracleParser to parse Oracle SQL into Calcite's internal AST, then transforms this into a RelNode tree. Calcite provides built-in validation, type inference, and semantic analysis. The RelNode tree is database-agnostic: it represents the query's relational algebra (scans, filters, joins, projects, aggregates, sorts, set operations) without binding to any specific SQL dialect. This is the critical abstraction layer that makes cross-database translation possible.

**Phase 3 -- Optimization:** With the RelNode tree in hand, the middleware applies optimization rules. Some of these are standard relational algebra optimizations (predicate pushdown, join reordering, projection pruning) that Calcite provides out of the box. Others are DataMigrata-specific semantic conversion rules: converting an Oracle CONNECT BY node into either a recursive CTE or a HIERARCHYID-based query (depending on the target table's storage format), converting an Oracle DECODE expression into a CASE WHEN expression, converting an Oracle ROWNUM filter into a TOP clause or OFFSET-FETCH, and converting Oracle-specific function calls (NVL, SYSDATE, ADD_MONTHS, TO_DATE) into their MSSQL equivalents (ISNULL, GETDATE, DATEADD, CONVERT). This phase also handles the most complex translations: Virtual Private Database (VPD) predicates are converted to Row-Level Security (RLS) predicate functions, XMLType operations are converted to MSSQL XML data type operations with XQuery, and SDO_GEOMETRY spatial operations are converted to Geography/Geometry type operations.

**Phase 4 -- Code Generation:** The optimized RelNode tree is rendered as syntactically valid T-SQL. This includes handling MSSQL-specific syntax elements: HIERARCHYID method calls (GetAncestor, IsDescendantOf, GetLevel), FOR SYSTEM_TIME temporal queries, JSON_MODIFY and OPENJSON operations, XML DML modify() operations, MERGE statements with OUTPUT clause, and SESSION_CONTEXT calls. The generated T-SQL is then executed against the MSSQL target via a standard MSSQL driver connection.

**How this differs from the PostgreSQL focus:** The "Beyond the Black Box" analysis document uses PostgreSQL as its primary target example, since the open-source migration tooling ecosystem is dominated by PostgreSQL. DataMigrata targets MSSQL instead, which changes several key design decisions. MSSQL offers native data types that Oracle lacks (HIERARCHYID, the system-versioned temporal table declaration syntax, the XML native type with XML DML, the JSON native type with OPENJSON and FOR JSON). MSSQL also offers enterprise features like Always Encrypted, Service Broker, and Query Store that have no direct PostgreSQL equivalent. The code generation phase must therefore produce T-SQL that leverages these MSSQL-specific features, rather than generic SQL that would work on any database.

### 2.3 Protocol Emulation Layer

The middleware must emulate database wire protocols at the network level. This is the most technically challenging aspect of the system, and the area with the highest risk of incomplete compatibility.

**TNS Protocol (incoming, from application):** Oracle's Transparent Network Substrate (TNS) is the wire protocol that Oracle database clients use to communicate with Oracle Database. TNS handles connection establishment (including the Oracle Net Services listener handshake), authentication (including support for Oracle Authentication Services, wallet-based credentials, and Kerberos), SQL statement submission, result set retrieval, cursor management, LOB operations, and transaction control (COMMIT, ROLLBACK, SAVEPOINT). The middleware must implement enough of the TNS protocol to accept connections from unmodified Oracle drivers.

The minimum viable TNS implementation includes:
- Listener accept: accept incoming TCP connections on a configurable port.
- TNS handshake: respond to the Oracle Net Services connect packet with a valid accept packet.
- Authentication: support at least username/password authentication (basic SQL*Net authentication).
- SQL submission: receive SQL text in TNS data frames.
- Result set delivery: format query results as TNS result set frames (including column metadata, row data, and end-of-fetch markers).
- Cursor lifecycle: manage server-side cursor state for queries that return multiple fetches.
- Transaction control: handle COMMIT, ROLLBACK, and SAVEPOINT over TNS.
- Error delivery: return Oracle-format error codes and messages when MSSQL errors occur.

**TDS Protocol (outgoing, to MSSQL):** Tabular Data Stream (TDS) is the wire protocol used by Microsoft SQL Server. The middleware connects to MSSQL using a standard MSSQL driver (which speaks TDS natively). The middleware does not need to implement TDS itself; it uses an existing driver library (such as the `tedious` npm package for Node.js or the `pyodbc` library for Python) that handles TDS encoding and decoding.

Alternatively, the middleware may choose to bypass TDS entirely for internal communication and use the MSSQL ODBC or JDBC driver directly. The TDS implementation detail is encapsulated within the MSSQL driver library and does not leak into the middleware's architecture.

**Session State Management:** The middleware is stateful per connection. Each client connection maintains:

- Transaction state: whether a transaction is active, the isolation level (READ COMMITTED, SERIALIZABLE, etc.), and any savepoints.
- Session context: key-value pairs set via SESSION_CONTEXT (the MSSQL equivalent of Oracle's package variables and DBMS_SESSION.SET_CONTEXT).
- Temporary tables: local temporary tables (#temp) created during the session.
- Prepared statements: parameterized queries that have been parsed once and can be re-executed with different parameter values.
- Cursor state: active server-side cursors and their fetch positions.
- RowVersion tracking: ROWVERSION/TIMESTAMP columns used for optimistic concurrency.

The middleware maps Oracle session concepts to MSSQL session concepts:
- Oracle SESSIONTIMEZONE maps to MSSQL TIMEZONE offset.
- Oracle SYS_CONTEXT('USERENV', ...) maps to MSSQL SESSION_CONTEXT and system functions.
- Oracle package-level variables map to MSSQL temporary table storage or SESSION_CONTEXT.
- Oracle DBMS_OUTPUT buffer maps to MSSQL PRINT/RAISERROR output capture.

### 2.4 Object Storage Layer (MinIO)

**Why MinIO and not AWS S3:**

MinIO is a high-performance object storage server that is fully compatible with the Amazon S3 API. Unlike AWS S3, MinIO runs on-premises or in any cloud environment, giving organizations full data sovereignty. For a middleware that manages enterprise database migration, data sovereignty is often a hard requirement: regulated industries (healthcare, finance, government) cannot send database content to public cloud storage.

MinIO is deployed as a Docker container alongside the MSSQL instance, making the entire DataMigrata stack deployable with a single docker-compose file. It requires no external network access and no AWS account. It is free and open-source (Apache 2.0 license).

**What goes into object storage:**

The middleware implements a data classification engine that determines whether a given piece of data belongs in MSSQL relational storage or MinIO object storage. The classification rules are:

1. **XML documents larger than 2MB:** Stored as objects in MinIO (bucket: `xmldata`). The MSSQL table contains a VARCHAR column with the MinIO object key and metadata columns for quick querying (document ID, root element name, creation timestamp). Small XML documents remain in MSSQL as the native XML data type, benefiting from XML indexes and XQuery support.

2. **JSON payloads larger than 2MB:** Stored as objects in MinIO (bucket: `jsondata`). Similar metadata pattern as XML. Smaller JSON remains in MSSQL as the NVARCHAR type, benefiting from JSON_PATH, OPENJSON, and JSON_MODIFY functions.

3. **LOB columns (BLOB, CLOB, NCLOB):** Oracle LOB data types that store images, documents, or large text bodies are stored in MinIO (bucket: `lobdata`). The MSSQL column stores the MinIO object key as a VARCHAR(512) instead of the actual content. The middleware intercepts LOB read and write operations and redirects them to MinIO, transparent to the application.

4. **Audit logs and event history:** Long-term audit data is written to MinIO (bucket: `auditlogs`) in Parquet or JSON format. Summary tables in MSSQL provide recent data for interactive queries. This follows a hot/warm/cold tiering strategy where recent data is in MSSQL and historical data is in MinIO.

5. **Database snapshots and backups:** Periodic exports of the MSSQL database state can be stored in MinIO for point-in-time recovery.

**How the middleware decides (polyglot persistence strategy):**

The data classification engine applies rules in order of priority:

```
Classification Rules (evaluated per column per row):
1. Is the column a declared LOB type in the Oracle source?
   YES -> Store in MinIO, reference in MSSQL
2. Is the column value > 2MB?
   YES -> Store in MinIO, reference in MSSQL
3. Is the column XML or JSON data?
   YES (and <= 2MB) -> Store natively in MSSQL
   YES (and > 2MB)  -> Store in MinIO, reference in MSSQL
4. Is the column structured relational data?
   YES -> Store in MSSQL (optimized representation)
5. Is the data an audit log entry older than 90 days?
   YES -> Store in MinIO, summary in MSSQL
```

This strategy follows the polyglot persistence principle described in the "Beyond the Black Box" analysis (Section 5.3), which recognizes that a single database engine is not the optimal storage for every type of data. The middleware manages this complexity so that the application does not need to be aware of it.

---

## 3. Data Layout Strategy: Optimized Representation on Target

### 3.1 Core Principle: NOT a 1:1 Copy

The fundamental principle of DataMigrata's data layout strategy is that the MSSQL target stores data in the most performant physical representation that MSSQL supports -- which is structurally different from the Oracle source. The middleware is not creating a copy of the Oracle database in MSSQL. It is creating a purpose-built MSSQL database that semantically represents the same data but uses MSSQL's most efficient storage mechanisms.

This means:
- The schema on MSSQL may have more tables, fewer tables, or differently structured tables than Oracle.
- Data types are chosen for MSSQL performance, not Oracle compatibility.
- Indexes are designed for the MSSQL query optimizer, not copied from Oracle.
- Table structures leverage MSSQL-specific features (temporal versioning, memory optimization, columnstore, partitioning) that Oracle either lacks or implements differently.
- The middleware maintains a semantic mapping registry that records how each Oracle entity maps to its MSSQL optimized equivalent.

**Concrete examples of structural differences:**

Oracle stores hierarchical data using an adjacency list (parent-child foreign key) and queries it with CONNECT BY. MSSQL's HIERARCHYID data type stores the entire hierarchy path in a single varbinary column, enabling subtree queries without recursion. The middleware stores the data in HIERARCHYID format on MSSQL and translates CONNECT BY queries to HIERARCHYID operations on read.

Oracle's Materialized Views are pre-computed query results that must be manually or periodically refreshed. MSSQL's Indexed Views (with SCHEMABINDING) are automatically maintained by the database engine -- any change to the base table automatically updates the indexed view. The middleware maps Oracle Materialized Views to MSSQL Indexed Views, and the automatic maintenance eliminates the need for Oracle-style refresh jobs.

Oracle's Virtual Private Database (VPD) adds security predicates to queries based on session context. MSSQL's Row-Level Security (RLS) achieves the same result using inline table-valued functions as filter predicates. The middleware translates VPD policies to RLS predicate functions, and the session context mapping (Oracle DBMS_SESSION to MSSQL SESSION_CONTEXT) connects the two.

### 3.2 Schema Transformation Rules

The following table documents the complete Oracle-to-MSSQL schema transformation rules, derived from the DataMigrata repository's PROJECT_PLAN.md and the existing demonstration database schema:

| Oracle Feature | MSSQL Target Representation | Transformation Rule |
|---|---|---|
| CONNECT BY hierarchy (adjacency list) | HIERARCHYID column in dedicated OrgChart table + recursive CTE for ad-hoc queries | Extract hierarchy from adjacency list, store as HIERARCHYID. Maintain both representations during initial migration. Map CONNECT BY queries to HIERARCHYID.GetAncestor/IsDescendantOf operations where possible, fall back to recursive CTE for complex path queries. |
| DECODE(expr, a, b, c, d, e) | CASE WHEN expr = a THEN b WHEN expr = c THEN d ELSE e END | Direct syntactic translation. DECODE is Oracle-specific; CASE is standard SQL. Calcite handles this in the IR phase. |
| NVL(expr, default) | ISNULL(expr, default) or COALESCE(expr, default) | Direct function mapping. COALESCE is preferred when multiple fallback values are needed (NVL2 behavior). |
| ROWNUM <= N | TOP N or OFFSET 0 ROWS FETCH NEXT N ROWS ONLY | ROWNUM in WHERE clause is translated to TOP in SELECT. For pagination, Oracle's OFFSET/FETCH maps to MSSQL's OFFSET/FETCH (both supported). |
| (+) outer join syntax | LEFT JOIN / RIGHT JOIN ON condition | Oracle's proprietary (+) notation is converted to ANSI-standard JOIN syntax during AST-to-IR transformation. |
| DUAL table | No table needed (SELECT without FROM) | MSSQL does not require DUAL. Oracle's SELECT 1 FROM DUAL becomes SELECT 1 in T-SQL. |
| SYSDATE | GETDATE() or SYSUTCDATETIME() | Oracle's SYSDATE returns server date/time; MSSQL's GETDATE() returns local, SYSUTCDATETIME() returns UTC. The middleware maps based on the Oracle NLS settings. |
| TO_DATE(string, format) | CONVERT(DATE, string, style) or TRY_CONVERT | Oracle date format strings (e.g., 'YYYY-MM-DD') are mapped to MSSQL style codes (e.g., 23 for ISO 8601). |
| XMLType column | XML native data type with XML indexes | Oracle's XMLType becomes MSSQL's XML type. XML Schema Collections are created for typed XML. Primary XML index and PATH/VALUE/PROPERTY secondary indexes are created for query performance. XML DML modify() operations translate directly (this is MSSQL-only functionality). |
| JSON (12c+ JSON column) | NVARCHAR(MAX) with JSON functions | Oracle stores JSON in VARCHAR2 or CLOB with check constraints. MSSQL stores JSON in NVARCHAR(MAX) and provides JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON, and FOR JSON. The middleware maps Oracle JSON functions (JSON_EXISTS, JSON_VALUE, JSON_TABLE) to MSSQL equivalents. |
| Materialized View | Indexed View (WITH SCHEMABINDING) + unique clustered index | Oracle MVs require manual refresh. MSSQL Indexed Views are auto-maintained. The SCHEMABINDING requirement means all referenced columns must be schema-qualified. Aggregations must use COUNT_BIG (not COUNT). |
| Virtual Private Database (VPD) | Row-Level Security (RLS) with inline TVF predicate | Oracle VPD adds predicates via policy functions. MSSQL RLS attaches a security predicate function to a table. The middleware maps Oracle's DBMS_SESSION context to MSSQL's SESSION_CONTEXT and translates the predicate logic. |
| Data Redaction | Dynamic Data Masking (column-level) | Oracle Data Redaction masks column values at query time. MSSQL Dynamic Data Masking applies masking functions (email(), partial(), default()) at the column definition level. Both operate transparently to the application. |
| SDO_GEOMETRY | Geography or Geometry type | Oracle's SDO_GEOMETRY supports geodetic and planar coordinates. MSSQL splits these into Geography (SRID 4326, ellipsoidal calculations) and Geometry (planar calculations). The middleware chooses based on the SRID of the source data. Spatial indexes use GEOGRAPHY_GRID tessellation. |
| Range partitioning | Partition function + partition scheme + partitioned table | Oracle's partition tables by range, list, or hash. MSSQL uses CREATE PARTITION FUNCTION and CREATE PARTITION SCHEME. The middleware generates these DDL statements from the Oracle partition metadata. |
| PL/SQL packages | Schema containing stored procedures + CLR assemblies | Oracle packages group related procedures, functions, and variables. MSSQL uses schemas for grouping and separate stored procedures. Package-level variables map to SESSION_CONTEXT or temporary tables. Complex logic may use CLR assemblies for .NET integration. |
| Advanced Queuing (AQ) | Service Broker | Oracle AQ provides message queuing between database sessions. MSSQL Service Broker provides native transactional messaging with queues, services, contracts, and message types. The middleware translates AQ enqueue/dequeue to Service Broker BEGIN DIALOG/SEND/RECEIVE. |
| Transparent Data Encryption (TDE) | TDE + Always Encrypted | Both databases support TDE for data-at-rest encryption. MSSQL additionally offers Always Encrypted for column-level encryption where the client controls the keys. The middleware supports both approaches. |
| Fine-Grained Auditing | SQL Server Audit Specifications | Oracle FGA creates audit policies on specific table/column conditions. MSSQL Audit Specifications can audit at the server or database level. The middleware maps audit policies to equivalent MSSQL specifications. |
| Flashback Query (AS OF) | Temporal table FOR SYSTEM_TIME AS OF | Oracle Flashback Query uses UNDO segments and is limited by UNDO retention. MSSQL temporal tables maintain a companion history table with SYSTEM_TIME period. The middleware translates Oracle AS OF TIMESTAMP queries to MSSQL FOR SYSTEM_TIME AS OF queries. |
| Flashback Data Archive (FDA) | Temporal table with history retention | Oracle FDA stores historical data for defined retention periods. MSSQL temporal tables + history table with optional partitioning provide equivalent functionality. The middleware configures history table retention policies. |
| DBMS_CRYPTO | Symmetric keys + certificates + hierarchy (SMK->DMK->Cert->Key) | Oracle's DBMS_CRYPTO provides encryption/decryption functions. MSSQL uses a key hierarchy: Service Master Key -> Database Master Key -> Certificate -> Symmetric Key. The middleware translates DBMS_CRYPTO.ENCRYPT/DECRYPT to EncryptByKey/DecryptByKey. |
| VARRAY / TABLE types | User-Defined Table Types + Table-Valued Parameters (TVPs) | Oracle collection types (VARRAY, TABLE) become MSSQL User-Defined Table Types. These types are used as Table-Valued Parameters for bulk operations, providing significant performance benefits for set-based operations. |
| Autonomous transactions | In-memory OLTP with natively compiled stored procedures | Oracle autonomous transactions execute independently of the parent transaction. MSSQL In-Memory OLTP provides lock-free, latch-free execution that eliminates blocking contention, achieving the same concurrency benefit through a different mechanism. |
| Bitmap indexes | Columnstore indexes | Oracle bitmap indexes are optimized for low-cardinality columns in data warehouse queries. MSSQL columnstore indexes provide equivalent (or superior) compression and batch-mode processing. Columnstore is available in MSSQL Standard Edition. |
| Parallel Query | Batch mode + columnstore parallelism | Oracle parallel query distributes work across multiple processes. MSSQL batch mode execution on columnstore indexes provides equivalent parallelism with less overhead. The MAXDOP query hint controls parallelism degree. |
| (+) outer join syntax | ANSI JOIN syntax | See above. This is a syntax-only transformation handled in the parser. |

**Denormalization decisions for performance:**

The middleware may choose to denormalize certain data structures on the MSSQL target when the query patterns justify it. Examples from the demonstration database:

- The `HR.Employees` table includes a persisted computed column `IsActive` that is derived from `TerminationDate IS NULL`. This is a denormalization that avoids the application having to compute this on every query.
- The `Sales.Products` table includes a persisted computed column `SearchVector` that concatenates ProductName, Category, and SubCategory for full-text indexing. This is a denormalization that enables full-text search without joining multiple columns at query time.
- The `Sales.Transactions` table includes a persisted computed column `TotalAmount` that calculates `Quantity * UnitPrice * (1 - DiscountPct)`. This pre-computes the total on write, avoiding repeated calculation on read.

**Index strategy for the target:**

The middleware creates indexes on the MSSQL target based on analysis of the Oracle source's access patterns, not by copying Oracle indexes. The index types used include:

- **Clustered columnstore index (CCI):** Created on analytical tables (`Sales.Transactions`, `Archive.OldTransactions`) for batch-mode query execution. Columnstore provides 10x compression ratios and eliminates row-level overhead for full-table scans.
- **Spatial index:** Created on geography columns (`Sales.Transactions.Region`) using GEOGRAPHY_GRID tessellation for proximity and distance queries.
- **Hash index:** Created on memory-optimized tables (`Sales.HighSpeedLookup`) for point-lookup performance. Hash indexes provide O(1) lookup for equality predicates.
- **HIERARCHYID primary key:** The `HR.OrgChart` table uses HIERARCHYID as the clustered primary key, which automatically stores nodes in depth-first order, making subtree scans contiguous on disk.
- **Full-text index:** Created on the `SearchVector` persisted computed column in `Sales.Products` for natural language search.
- **XML index:** Primary XML index plus PATH secondary index on the `EmployeeData` XML column in `HR.Employees` for XPath query acceleration.
- **Partitioned tables:** The `Sales.PartitionedSales` table is partitioned by year using `pf_TransactionYear` and `ps_TransactionYear`, enabling partition elimination for year-bounded queries.

### 3.3 Physical Storage Layout

The MSSQL target database (`MSSQL_Advanced_Demo` in the current PoC) is organized across 6 schemas with 12 tables:

```
Schema       Table                 Rows     Storage Engine           Key Features
-----------  --------------------  ------   ----------------------   ------------------------------------------
HR           Employees              5,000   Disk-based (rowstore)    Hierarchy, XML, Computed, RowVersion, DDM
HR           OrgChart                 ~100   Disk-based (rowstore)    HIERARCHYID PK, OrgLevel computed
Sales        Products               1,000   Disk-based (rowstore)    Full-text index, Persisted computed
Sales        Transactions           5,000   Disk-based (rowstore)    Temporal, JSON, Geography, Columnstore CCI
Sales        TransactionsHistory    varies  System-managed            Auto-maintained by temporal versioning
Sales        CustomerCache          2,000   In-Memory OLTP (Hekaton)  Nonclustered PK, DURABILITY=SCHEMA_AND_DATA
Sales        HighSpeedLookup        1,000   In-Memory OLTP (Hekaton)  Hash index (BUCKET_COUNT=1M)
Sales        PartitionedSales      2,000   Disk-based (partitioned)  Partitioned by year (2021-2026)
Audit        EventLog               1,000   Disk-based (rowstore)    Sequence-driven PK
Security     SensitiveData            100   Disk-based (rowstore)    Encrypted columns (cert + symmetric key)
Archive      OldTransactions        3,000   Disk-based (rowstore)    Columnstore CCI for analytics
Staging      ETLSource                 500   Disk-based (rowstore)    MERGE/ETL staging area
```

**In-memory OLTP tables (Hekaton) for hot paths:**

Two tables (`Sales.CustomerCache` and `Sales.HighSpeedLookup`) use memory-optimized storage. These tables are designed for workloads with extreme concurrency requirements:

- Data resides entirely in memory (no disk I/O for reads).
- Row-level operations use latch-free data structures (no lock waits, no deadlock potential).
- Hash indexes provide deterministic O(1) point lookups.
- Natively compiled stored procedures can access these tables with minimal instruction path.

The `CustomerCache` table stores frequently accessed customer data (name, email, region, total spent) in memory-optimized format. The application might query this table thousands of times per second during peak load. On Oracle, this data would be in a standard heap table with buffer cache hits. On MSSQL, the memory-optimized table eliminates the buffer management overhead entirely.

**Columnstore indexes for analytics queries:**

The `Sales.Transactions` table has a nonclustered columnstore index (`IX_CS_Transactions`) on the columns `EmployeeID, ProductID, TotalAmount, TransactionDate, PaymentStatus`. This enables:

- Batch-mode execution for analytical aggregation queries (GROUP BY, SUM, AVG).
- 10x data compression compared to rowstore.
- Elimination of row-level overhead for full-table scans (no per-row locking, no per-row versioning).

The `Archive.OldTransactions` table is designed for analytical workloads with its year-based partitioning and planned columnstore index.

**Temporal tables for audit and history:**

The `Sales.Transactions` table is a system-versioned temporal table. MSSQL automatically maintains a history table (`Sales.TransactionsHistory`) that records every row change with `ValidFrom` and `ValidTo` timestamps. This provides:

- Point-in-time queries: `FOR SYSTEM_TIME AS OF <timestamp>`
- Range queries: `FOR SYSTEM_TIME BETWEEN <start> AND <end>`
- Full history: `FOR SYSTEM_TIME ALL`

The history table is automatically managed -- no triggers, no application logic, no manual refresh jobs. This is a significant improvement over Oracle's Flashback Query approach, which requires UNDO segment configuration and is limited by retention settings.

### 3.4 Back-Transformation: MSSQL Optimized Format to Oracle Source Format

When the application reads data from the middleware, the middleware must present the result set in exactly the format that the Oracle application expects. This is the back-transformation step, and it is the defining characteristic that separates DataMigrata from a simple query translator.

**How back-transformation works:**

1. The application sends an Oracle SQL query (e.g., a CONNECT BY query).
2. The middleware translates this to an optimized T-SQL query (e.g., a HIERARCHYID-based query).
3. The T-SQL executes on MSSQL and returns a result set.
4. The middleware transforms the MSSQL result set to match what Oracle would have returned:
   - Column names are mapped from MSSQL names to Oracle names.
   - Data types are converted (e.g., HIERARCHYID varbinary path is converted to the LEVEL pseudocolumn and PRIOR format).
   - Row ordering is adjusted (HIERARCHYID naturally sorts in depth-first order, which matches CONNECT BY behavior).
   - NULL handling is adjusted if Oracle and MSSQL treat NULLs differently in the specific context.

**Example: HIERARCHYID to CONNECT BY result set:**

Oracle CONNECT BY query:
```sql
SELECT LEVEL, EmployeeID, PRIOR EmployeeID AS ManagerID, FullName
FROM Employees
CONNECT BY PRIOR EmployeeID = ManagerID
START WITH ManagerID IS NULL;
```

MSSQL HIERARCHYID query:
```sql
SELECT
    o.OrgNode.GetLevel() AS OrgLevel,
    o.EmployeeID,
    o.OrgNode.GetAncestor(1).ToString() AS ParentPath,
    e.FullName
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrgNode;
```

Back-transformation: The middleware maps `OrgLevel` to `LEVEL`, parses `ParentPath` to extract the integer ManagerID, and formats the result set to match the Oracle output column names and ordering. The application receives data that looks exactly like what Oracle would have returned, even though the underlying storage and execution mechanism is completely different.

**Example: Temporal table to Oracle Flashback Query:**

Oracle Flashback Query:
```sql
SELECT * FROM Transactions AS OF TIMESTAMP (SYSDATE - 1);
```

MSSQL Temporal Query:
```sql
SELECT * FROM Sales.Transactions
FOR SYSTEM_TIME AS OF DATEADD(DAY, -1, SYSUTCDATETIME());
```

Back-transformation: The middleware strips the MSSQL-specific `ValidFrom` and `ValidTo` columns (which are HIDDEN in the table definition, so they are not included in SELECT * by default -- a convenient alignment). The result set column names and data types match the Oracle format.

**Example: Indexed View to Materialized View query:**

Oracle Materialized View:
```sql
SELECT * FROM MV_ProductSummary WHERE Category = 'Software';
```

MSSQL Indexed View (accessed with NOEXPAND hint):
```sql
SELECT * FROM Sales.vw_ProductSummary WITH (NOEXPAND)
WHERE Category = 'Software';
```

Back-transformation: The middleware maps the view name from Oracle's naming convention to MSSQL's naming convention. The `NOEXPAND` hint ensures the query uses the materialized (indexed) data rather than expanding the view definition. The result set is identical.

**Example: RLS to VPD result set:**

When Row-Level Security filters the result set based on SESSION_CONTEXT, the middleware must ensure that the session context is set correctly before executing the query. The Oracle application sets VPD context via `DBMS_SESSION.SET_CONTEXT`. The middleware intercepts this call and maps it to `sp_set_session_context`. The RLS predicate function then uses this session context to filter rows, producing the same result that Oracle's VPD would have produced.

---

## 4. The 50 MSSQL Operations as USPs

### 4.1 Why These 50 Operations Matter

The DataMigrata repository defines 50 sophisticated MSSQL operations organized across 9 categories. These operations are not arbitrary demonstrations -- they are a curated set that proves MSSQL's superiority as a migration target by showcasing capabilities that either do not exist in Oracle or are implemented more efficiently in MSSQL. Each operation represents a concrete translation challenge that the middleware must solve.

These are the "Alleinstellungsmerkmale" (unique selling points) -- the capabilities that make MSSQL a compelling target for Oracle migration, and that a PostgreSQL target would struggle to match. Together, they demonstrate that MSSQL is not just "another relational database" but a platform with distinctive architectural strengths in hierarchical data, semi-structured data processing, temporal analysis, spatial computation, in-memory performance, and security.

The 50 operations serve three purposes:
1. **Validation set:** Each operation must execute correctly on the existing MSSQL Docker instance with the demonstration data. This proves the target environment works.
2. **Translation test suite:** Each operation has an Oracle equivalent that the middleware must translate. Successful translation of all 50 operations validates the compiler pipeline.
3. **Feature demonstration:** Each operation demonstrates an MSSQL capability that the middleware can leverage for performance optimization.

### 4.2 Operation Categories and Oracle Translation

#### Category 1: Hierarchical and Recursive Queries (Operations 1-5)

**What it does:** MSSQL provides two distinct mechanisms for hierarchical data: Recursive Common Table Expressions (CTEs) following the SQL:1999 standard, and the proprietary HIERARCHYID data type that stores tree structures in a compact varbinary format. Operations 1-5 demonstrate both approaches.

**Oracle implementation:** Oracle's CONNECT BY syntax with PRIOR for parent-child traversal and LEVEL for depth indication. Oracle has no equivalent to HIERARCHYID; all hierarchy operations use recursive adjacency list joins.

**MSSQL implementation:** Recursive CTEs with UNION ALL for standard hierarchical queries. HIERARCHYID for optimized tree operations: GetAncestor(n) for navigating up the tree, IsDescendantOf() for subtree containment checks, GetLevel() for depth, and ToString() for human-readable path representation. The HIERARCHYID column serves as the clustered primary key, storing nodes in depth-first order for contiguous subtree scans.

**Middleware translation:** CONNECT BY queries with simple parent-child relationships translate to recursive CTEs. CONNECT BY queries that can leverage pre-computed hierarchy paths translate to HIERARCHYID operations, which execute orders of magnitude faster. The middleware maintains both the adjacency list (in `HR.Employees.ManagerID`) and the HIERARCHYID representation (in `HR.OrgChart.OrgNode`) to support both query patterns.

**Performance implications:** HIERARCHYID subtree queries are O(log n) with index support, compared to O(n) for recursive CTEs on adjacency lists. For the 5,000-employee dataset, this means subtree queries that would require multiple recursive joins on Oracle execute as single index seeks on MSSQL.

#### Category 2: XML Native Operations (Operations 6-10)

**What it does:** MSSQL provides a native XML data type with integrated XQuery support, XML DML (Data Manipulation Language) for in-place XML modification, and XML Schema Collections for typed XML validation. Operations 6-10 demonstrate XML modification, shredding (decomposing XML into relational rows), aggregation (producing XML from relational data), indexed querying, and typed XML.

**Oracle implementation:** Oracle's XMLType stores XML data with basic XQuery support. Oracle does not support XML DML (in-place modification of XML documents within a column). Oracle supports XML indexes but with different indexing strategies.

**MSSQL implementation:** The XML data type supports five methods: query() for XQuery extraction, value() for scalar extraction, exist() for existence checks, nodes() for shredding XML into relational rows, and modify() for XML DML operations (insert, delete, replace of XML nodes). Primary XML indexes plus PATH/VALUE/PROPERTY secondary indexes accelerate XQuery expressions.

**Middleware translation:** Oracle XMLType column declarations map to MSSQL XML type. Oracle's XMLTable and XMLCast functions map to MSSQL nodes() and value() methods. XML DML modify() operations are MSSQL-specific; the middleware generates these when the Oracle application needs to modify XML content in-place. XML Schema Collections are created from Oracle's registered XML schemas.

**Performance implications:** XML DML modify() eliminates the need to extract, parse, modify, and re-serialize entire XML documents. Combined with XML indexes, XQuery operations can use index seeks instead of full document scans.

#### Category 3: JSON Native Operations (Operations 11-15)

**What it does:** MSSQL provides built-in JSON functions for querying, modifying, and generating JSON data from relational tables. Operations 11-15 demonstrate JSON path queries, hierarchical JSON generation, JSON modification, table-valued JSON parsing, and JSON array operations.

**Oracle implementation:** Oracle 12c introduced JSON support with JSON_VALUE, JSON_EXISTS, JSON_TABLE, and IS JSON check constraints. Oracle stores JSON in VARCHAR2 or CLOB columns. Oracle lacks JSON_MODIFY (cannot modify JSON in-place) and OPENJSON (cannot parse JSON into a table result set).

**MSSQL implementation:** JSON_VALUE for scalar extraction, JSON_QUERY for object/array extraction, OPENJSON for shredding JSON into relational rows (with explicit schema or default schema), JSON_MODIFY for in-place modification (update, append, delete properties), and FOR JSON PATH/ROOT for generating nested JSON from relational queries.

**Middleware translation:** Oracle JSON_VALUE maps directly to MSSQL JSON_VALUE. Oracle JSON_TABLE maps to OPENJSON WITH (explicit schema). Oracle's lack of JSON_MODIFY means that any Oracle application modifying JSON content must be doing so at the application level (extract, modify, re-insert). The middleware can optimize this by translating the pattern to a single JSON_MODIFY call. FOR JSON PATH/ROOT is MSSQL-specific and used for generating JSON responses from relational data.

**Performance implications:** OPENJSON with explicit schema is significantly faster than application-level JSON parsing because the database engine parses JSON directly without data transfer overhead. FOR JSON PATH generates nested JSON without the N+1 query problem that application-level JSON assembly would require.

#### Category 4: Temporal Tables (Operations 16-20)

**What it does:** MSSQL system-versioned temporal tables automatically maintain a full history of all data changes in a companion history table. Operations 16-20 demonstrate point-in-time queries (AS OF), range queries (BETWEEN), historical data analysis, point-in-time reconstruction, and version analytics.

**Oracle implementation:** Oracle Flashback Query reads UNDO segments to reconstruct historical data. This is limited by UNDO retention (typically hours, not years). Oracle Flashback Data Archive (FDA) stores historical data for defined retention periods but requires separate configuration and storage management. Neither approach is declarative -- they require administrative setup.

**MSSQL implementation:** Temporal tables are declared with `SYSTEM_VERSIONING = ON (HISTORY_TABLE = ...)`. Every INSERT, UPDATE, or DELETE automatically generates a history record. The `FOR SYSTEM_TIME` clause provides AS OF, BETWEEN, CONTAINED IN, and ALL temporal querying. The history table has HIDDEN period columns (ValidFrom, ValidTo) that are excluded from SELECT * results.

**Middleware translation:** Oracle's `AS OF TIMESTAMP (SYSDATE - INTERVAL '1' DAY)` maps to MSSQL's `FOR SYSTEM_TIME AS OF DATEADD(DAY, -1, SYSUTCDATETIME())`. Oracle's `VERSIONS BETWEEN TIMESTAMP` maps to `FOR SYSTEM_TIME BETWEEN`. The middleware converts Oracle date arithmetic functions to MSSQL DATEADD equivalents.

**Performance implications:** MSSQL temporal tables eliminate the need for triggers to track history. The history table is automatically indexed and maintained. Queries against the history table benefit from the same indexing strategy as the current table. For the demonstration database, the `Sales.TransactionsHistory` table grows automatically as transactions are modified.

#### Category 5: Advanced Views (Operations 21-30)

**What it does:** MSSQL supports indexed (materialized) views with SCHEMABINDING, partitioned views spanning multiple tables, CHECK OPTION views, INSTEAD OF triggers for updatable views, inline table-valued functions (parameterized views), PIVOT/UNPIVOT operations, recursive TVFs, GROUPING SETS, and window functions with framing. Operations 21-30 demonstrate all of these capabilities.

**Oracle implementation:** Oracle Materialized Views provide pre-computed query results with refresh mechanisms (complete, fast, force). Oracle does not support PIVOT/UNPIVOT as SQL operators (though 11g introduced PIVOT). Oracle's inline views are subqueries in the FROM clause. GROUPING SETS and window functions are supported in recent Oracle versions.

**MSSQL implementation:** Indexed Views (WITH SCHEMABINDING) are auto-maintained materialized views with unique clustered indexes. Partitioned views (UNION ALL across partitioned tables) enable cross-partition queries. INSTEAD OF triggers make complex views updatable. Inline TVFs are parameterized views that the optimizer can inline. PIVOT/UNPIVOT are first-class SQL operators.

**Middleware translation:** Oracle Materialized Views map to Indexed Views. Oracle's REFRESH COMPLETE becomes unnecessary (Indexed Views are always current). Oracle's DBMS_MVIEW.REFRESH calls are mapped to no-ops (or removed from application code). INSTEAD OF triggers translate directly. GROUPING SETS are functionally equivalent between Oracle and MSSQL.

**Performance implications:** Indexed Views with NOEXPAND hint eliminate the overhead of view definition evaluation. For the `Sales.vw_ProductSummary` view, the pre-aggregated data (COUNT_BIG, SUM, AVG by Category) is stored as a clustered index, making the view query a single index scan instead of a full table scan + aggregation.

#### Category 6: Spatial Data (Operations 31-35)

**What it does:** MSSQL provides native spatial data types (Geography for ellipsoidal calculations, Geometry for planar calculations), spatial indexes with tessellation, and spatial functions for distance, intersection, buffer, and containment calculations. Operations 31-35 demonstrate distance calculations, buffer analysis, multi-point routes, spatial index optimization, and multi-polygon territory analysis.

**Oracle implementation:** Oracle Spatial (SDO_GEOMETRY) provides similar spatial capabilities but is a separately licensed option (Spatial and Graph). Oracle's spatial indexing uses R-trees. Oracle supports both geodetic and planar coordinates in a single type.

**MSSQL implementation:** Geography type (SRID 4326) for accurate Earth-surface distance calculations using ellipsoidal models. Geometry type for planar coordinate systems. GEOGRAPHY_GRID tessellation for spatial indexes. Methods include STDistance (ellipsoidal distance in meters), STIntersects, STBuffer, STContains, STAsText, STLength.

**Middleware translation:** Oracle SDO_GEOMETRY maps to Geography (if SRID indicates geodetic coordinates) or Geometry (if SRID indicates planar coordinates). Oracle's SDO_DISTANCE maps to STDistance. Oracle's SDO_WITHIN_DISTANCE maps to STDistance with a threshold. The middleware must handle the type split (Oracle uses one type, MSSQL uses two) based on SRID analysis.

**Performance implications:** MSSQL spatial indexes use a multi-level grid tessellation that enables spatial predicates to use index seeks rather than full-table scans. For the demonstration data, distance queries against the 5,000-row `Sales.Transactions` table with geography coordinates benefit from the spatial index `SIDX_Transactions_Region`.

#### Category 7: Columnstore and In-Memory (Operations 36-40)

**What it does:** MSSQL provides columnstore indexes for analytical workloads and In-Memory OLTP (Hekaton) for high-concurrency operational workloads. Operations 36-40 demonstrate columnstore analytical queries, natively compiled stored procedures, hash index lookups, real-time operational analytics, and batch mode on rowstore.

**Oracle implementation:** Oracle In-Memory Column Store (IMCS) is an Enterprise Edition option that requires additional licensing. Oracle does not provide a general-purpose in-memory OLTP engine equivalent to Hekaton. Oracle's approach to in-memory optimization focuses on columnar compression for analytics, not lock-free row operations.

**MSSQL implementation:** Clustered Columnstore Index (CCI) stores data in columnar format with 10x compression. Nonclustered columnstore indexes add columnar processing to existing rowstore tables. In-Memory OLTP tables use lock-free data structures with hash and range indexes. Natively compiled stored procedures translate T-SQL to native machine code, bypassing the traditional query processor.

**Middleware translation:** Oracle bitmap indexes map to columnstore indexes. Oracle's In-Memory Column Store hint maps to columnstore index usage. Oracle's autonomous transactions map to in-memory OLTP tables for concurrency. The middleware's schema translation engine automatically applies columnstore to analytical tables and memory optimization to hot-path tables.

**Performance implications:** For the demonstration database, the `Sales.CustomerCache` (2,000 rows, memory-optimized) and `Sales.HighSpeedLookup` (1,000 rows, memory-optimized with hash index) provide sub-millisecond point lookups. The `Sales.Transactions` columnstore index enables aggregation queries over 5,000 rows to execute in batch mode, processing rows in batches rather than one at a time.

#### Category 8: Security and Encryption (Operations 41-45)

**What it does:** MSSQL provides a layered security architecture including Always Encrypted (client-side encryption), Row-Level Security (RLS), Dynamic Data Masking, SQL Server Audit, and certificate-based procedure signing. Operations 41-45 demonstrate column encryption/decryption, RLS predicate filtering, data masking, audit configuration, and signed stored procedures.

**Oracle implementation:** Oracle provides Transparent Data Encryption (TDE), Virtual Private Database (VPD), Data Redaction, Fine-Grained Auditing (FGA), and DBMS_CRYPTO. Oracle's security features are mature but configured differently from MSSQL's approach.

**MSSQL implementation:** The encryption key hierarchy (SMK -> DMK -> Certificate -> Symmetric Key) provides layered key management. RLS uses inline TVF predicates attached to tables via security policies. Dynamic Data Masking applies masking functions at the column definition level. SQL Server Audit captures server-level and database-level events. Certificates can sign stored procedures to grant permissions without direct role membership.

**Middleware translation:** Oracle TDE maps to MSSQL TDE. Oracle VPD maps to MSSQL RLS (see Section 3.4 for back-transformation details). Oracle Data Redaction maps to MSSQL Dynamic Data Masking. Oracle FGA maps to MSSQL Audit Specifications. Oracle DBMS_CRYPTO maps to MSSQL EncryptByKey/DecryptByKey with the key hierarchy.

**Performance implications:** RLS and Dynamic Data Masking add negligible overhead because they are evaluated by the query optimizer as additional predicates. The encryption/decryption operations add CPU overhead but this is unavoidable for encrypted data. The middleware can cache decrypted values in session state for frequently accessed encrypted data.

#### Category 9: Advanced Programmability (Operations 46-50)

**What it does:** MSSQL provides Table-Valued Parameters (TVPs) for bulk data transfer, MERGE with OUTPUT clause for upsert operations, TRY_CONVERT for safe type conversion, SESSION_CONTEXT for cross-request state, and CHANGETABLE for change tracking. Operations 46-50 demonstrate all of these capabilities.

**Oracle implementation:** Oracle's equivalent of TVPs is the VARRAY/TABLE type passed as PL/SQL collection parameters. Oracle's MERGE (UPSERT) was actually introduced before MSSQL's but lacks the OUTPUT clause for capturing merge actions. Oracle's exception handling (EXCEPTION WHEN OTHERS) provides type conversion error handling. Oracle's package variables provide cross-request state. Oracle's materialized view logs provide change tracking.

**MSSQL implementation:** User-Defined Table Types enable TVPs that pass entire result sets as stored procedure parameters. MERGE with OUTPUT $action captures which rows were inserted, updated, or deleted. TRY_CONVERT returns NULL instead of throwing an error on conversion failure. SESSION_CONTEXT (introduced in SQL Server 2016) provides key-value state scoped to the session. CHANGETABLE(CHANGES) provides incremental change tracking without triggers.

**Middleware translation:** Oracle VARRAY parameters map to MSSQL TVPs with User-Defined Table Types. Oracle MERGE maps to MSSQL MERGE (both support WHEN MATCHED/NOT MATCHED). Oracle's EXCEPTION handling for type conversion maps to TRY_CONVERT/TRY_CAST. Oracle DBMS_SESSION.SET_CONTEXT maps to sp_set_session_context. Oracle materialized view logs map to CHANGETABLE.

**Performance implications:** TVPs eliminate the N+1 insert problem by passing entire data sets in a single round trip. MERGE with OUTPUT enables single-statement upserts with action tracking. CHANGETABLE enables incremental ETL without scanning the entire source table.

### 4.3 Key Translation Examples

The following detailed examples illustrate the end-to-end translation process for seven high-value Oracle-to-MSSQL conversions. Each example shows the Oracle source syntax, the MSSQL target syntax, and the middleware's role in translating between them.

#### Example 1: CONNECT BY to HIERARCHYID

**Oracle source:**
```sql
SELECT LEVEL, EMPLOYEE_ID, FULL_NAME, MANAGER_ID
FROM EMPLOYEES
CONNECT BY PRIOR EMPLOYEE_ID = MANAGER_ID
START WITH MANAGER_ID IS NULL
ORDER SIBLINGS BY FULL_NAME;
```

**MSSQL target (using HIERARCHYID):**
```sql
SELECT
    o.OrgNode.GetLevel() AS LEVEL,
    o.EmployeeID AS EMPLOYEE_ID,
    e.FullName AS FULL_NAME,
    -- ManagerID derived from HIERARCHYID ancestor path
    CASE WHEN o.OrgNode.GetLevel() > 1
         THEN (SELECT TOP 1 o2.EmployeeID
               FROM HR.OrgChart o2
               WHERE o.OrgNode.IsDescendantOf(o2.OrgNode) = 1
               AND o2.OrgNode.GetLevel() = o.OrgNode.GetLevel() - 1)
         ELSE NULL
    END AS MANAGER_ID
FROM HR.OrgChart o
JOIN HR.Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrgNode;
```

**Middleware behavior:** The parser identifies the CONNECT BY clause, START WITH clause, LEVEL pseudocolumn, and PRIOR operator. The IR phase creates a hierarchical scan node with parent-child relationship metadata. The optimization phase checks the schema mapping registry, finds that the employees table has a corresponding HIERARCHYID representation in the OrgChart table, and rewrites the query to use HIERARCHYID methods. The code generation phase produces the T-SQL above. On result return, the middleware maps the column names to Oracle conventions.

**Performance delta:** On Oracle, this query performs N recursive joins (one per level) over the adjacency list. On MSSQL with HIERARCHYID, it is a single clustered index scan (depth-first order) with no recursion needed.

#### Example 2: DECODE to CASE

**Oracle source:**
```sql
SELECT DECODE(DEPARTMENT,
    'Engineering', 'ENG',
    'Marketing', 'MKT',
    'Sales', 'SLS',
    'Other') AS DEPT_CODE
FROM EMPLOYEES;
```

**MSSQL target:**
```sql
SELECT CASE DEPARTMENT
    WHEN 'Engineering' THEN 'ENG'
    WHEN 'Marketing' THEN 'MKT'
    WHEN 'Sales' THEN 'SLS'
    ELSE 'Other'
END AS DEPT_CODE
FROM HR.Employees;
```

**Middleware behavior:** The parser identifies the DECODE function call with its expression-search-result pairs. The IR phase converts DECODE to a Calcite CASE expression. Calcite handles this natively since DECODE is a recognized Oracle function in Calcite's OracleParser. The code generation phase outputs standard CASE WHEN syntax, which is identical in both Oracle and MSSQL. This is one of the simplest translations and illustrates how Calcite's built-in SQL dialect support handles many conversions automatically.

#### Example 3: Materialized View to Indexed View

**Oracle DDL:**
```sql
CREATE MATERIALIZED VIEW MV_ProductSummary
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT Category, COUNT(*) AS ProductCount, SUM(BasePrice) AS TotalPrice
FROM Products
GROUP BY Category;
```

**MSSQL DDL:**
```sql
CREATE VIEW Sales.vw_ProductSummary WITH SCHEMABINDING
AS
SELECT
    p.Category,
    COUNT_BIG(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    AVG(p.BasePrice) AS AvgBasePrice,
    SUM(p.CostPrice) AS TotalCostPrice
FROM dbo.Products p
GROUP BY p.Category;
GO
CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSummary
ON Sales.vw_ProductSummary(Category);
```

**Middleware behavior:** During schema migration (Phase 3), the middleware translates the Oracle Materialized View DDL to an Indexed View DDL. Key transformations: (1) MATERIALIZED VIEW becomes VIEW with SCHEMABINDING; (2) REFRESH COMPLETE is discarded (Indexed Views are auto-maintained); (3) COUNT(*) becomes COUNT_BIG(*) (required for Indexed Views); (4) Schema qualification is added (required by SCHEMABINDING); (5) A unique clustered index is created on the view.

At runtime, when the application queries `SELECT * FROM MV_ProductSummary`, the middleware translates the table reference to `Sales.vw_ProductSummary WITH (NOEXPAND)` to ensure the materialized data is used rather than expanding the view definition. The NOEXPAND hint is critical: without it, the optimizer might choose to ignore the materialized data and recompute the aggregation from the base table.

**Performance delta:** On Oracle, the Materialized View must be refreshed periodically (REFRESH COMPLETE or REFRESH FAST), meaning the data may be stale between refreshes. On MSSQL, the Indexed View is always current because the engine updates it atomically with every base table modification. There is no staleness window.

#### Example 4: VPD to Row-Level Security

**Oracle VPD setup:**
```sql
-- Policy function
CREATE OR REPLACE FUNCTION emp_policy(
    p_schema IN VARCHAR2, p_object IN VARCHAR2)
RETURN VARCHAR2 IS
    v predicate VARCHAR2(4000);
BEGIN
    v_predicate := 'EMPLOYEE_ID = SYS_CONTEXT(''USERENV'', ''SESSION_USER_ID'')';
    RETURN v_predicate;
END;

-- Apply policy
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema => 'HR',
        object_name   => 'EMPLOYEES',
        policy_name   => 'EMP_FILTER',
        function_schema => 'HR',
        policy_function  => 'emp_policy');
END;
```

**MSSQL RLS setup:**
```sql
-- Predicate function (inline TVF)
CREATE FUNCTION Security.fn_securitypredicate(@EmployeeID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_securitypredicate_result
WHERE
    @EmployeeID = CAST(SESSION_CONTEXT(N'UserEmployeeID') AS INT)
    OR IS_MEMBER('db_ManagerRole') = 1;
GO

-- Apply policy
CREATE SECURITY POLICY Security.EmployeeFilterPolicy
    ADD FILTER PREDICATE Security.fn_securitypredicate(EmployeeID)
        ON HR.Employees
    WITH (STATE = ON, SCHEMABINDING = ON);
```

**Middleware behavior:** The schema translation engine converts the Oracle VPD policy function to an MSSQL inline TVF predicate function. The middleware maps `SYS_CONTEXT('USERENV', 'SESSION_USER_ID')` to `SESSION_CONTEXT(N'UserEmployeeID')`. The `DBMS_RLS.ADD_POLICY` call is mapped to the `CREATE SECURITY POLICY` statement. At runtime, when the application calls `DBMS_SESSION.SET_CONTEXT('USERENV', 'SESSION_USER_ID', '12345')`, the middleware translates this to `sp_set_session_context 'UserEmployeeID', 12345`.

**Performance delta:** Both VPD and RLS add a predicate to every query against the protected table. The overhead is comparable. However, MSSQL RLS predicate functions can be inlined by the optimizer (when defined as inline TVFs), which can result in more efficient execution plans than Oracle's approach of appending a string predicate.

#### Example 5: PL/SQL Packages to Schema + Stored Procedures

**Oracle package:**
```sql
CREATE OR REPLACE PACKAGE emp_pkg AS
    -- Package variable
    v_company_name VARCHAR2(100) := 'DataMigrata Corp';

    -- Function declaration
    FUNCTION get_salary(p_emp_id NUMBER) RETURN NUMBER;

    -- Procedure declaration
    PROCEDURE raise_salary(p_emp_id NUMBER, p_pct NUMBER);
END emp_pkg;

CREATE OR REPLACE PACKAGE BODY emp_pkg AS
    FUNCTION get_salary(p_emp_id NUMBER) RETURN NUMBER IS
        v_salary NUMBER;
    BEGIN
        SELECT salary INTO v_salary FROM employees WHERE employee_id = p_emp_id;
        RETURN v_salary;
    END;

    PROCEDURE raise_salary(p_emp_id NUMBER, p_pct NUMBER) IS
    BEGIN
        UPDATE employees SET salary = salary * (1 + p_pct/100) WHERE employee_id = p_emp_id;
        COMMIT;
    END;
END emp_pkg;
```

**MSSQL equivalent:**
```sql
-- Schema for grouping (replaces package namespace)
CREATE SCHEMA EmpPkg;
GO

-- Store package variable in SESSION_CONTEXT or a config table
-- (Set at session initialization)
-- EXEC sp_set_session_context 'CompanyName', 'DataMigrata Corp';

-- Function (maps to scalar function)
CREATE FUNCTION EmpPkg.GetSalary(@EmpID INT)
RETURNS DECIMAL(18,2)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Salary DECIMAL(18,2);
    SELECT @Salary = Salary FROM HR.Employees WHERE EmployeeID = @EmpID;
    RETURN @Salary;
END;
GO

-- Procedure (maps to stored procedure)
CREATE PROCEDURE EmpPkg.RaiseSalary
    @EmpID INT,
    @Pct DECIMAL(5,2)
AS
BEGIN
    UPDATE HR.Employees SET Salary = Salary * (1 + @Pct/100) WHERE EmployeeID = @EmpID;
END;
GO
```

**Middleware behavior:** This is one of the most complex translations. The middleware's stored procedure translation engine (Phase 4) handles it as follows:
1. Package name (`emp_pkg`) becomes a schema name (`EmpPkg`).
2. Package-level variables (`v_company_name`) are stored in SESSION_CONTEXT or a configuration table, initialized at session start.
3. Package functions map to scalar user-defined functions.
4. Package procedures map to stored procedures.
5. PL/SQL-specific syntax (IS/BEGIN/END, INTO clause for SELECT) is converted to T-SQL syntax (AS/BEGIN/END, variable assignment syntax).
6. The COMMIT inside the procedure is handled differently: Oracle's autonomous commit is explicit; MSSQL procedures run in the caller's transaction context by default. The middleware must handle transaction semantics carefully.

**Performance implications:** MSSQL stored procedures are compiled and cached, similar to Oracle's PL/SQL compiled code. Performance should be comparable for straightforward translations. For complex procedural logic with loops and cursors, the middleware may choose to use natively compiled stored procedures (memory-optimized) for the most performance-critical code paths.

#### Example 6: XMLType to XML Native Type

**Oracle source:**
```sql
-- Create table with XMLType
CREATE TABLE employees_xml (
    emp_id NUMBER PRIMARY KEY,
    emp_data XMLTYPE
);

-- Query with XMLType methods
SELECT emp_id,
       EXTRACTVALUE(emp_data, '/Employee/Skills/Skill[1]') AS primary_skill
FROM employees_xml
WHERE EXISTSNODE(emp_data, '/Employee/Skills/Skill[@level="Expert"]') = 1;
```

**MSSQL target:**
```sql
-- Create table with XML type
CREATE TABLE HR.EmployeesXML (
    EmpID INT PRIMARY KEY,
    EmpData XML
);

-- Query with XML methods
SELECT EmpID,
       EmpData.value('(/Employee/Skills/Skill)[1]', 'NVARCHAR(100)') AS primary_skill
FROM HR.EmployeesXML
WHERE EmpData.exist('/Employee/Skills/Skill[@level="Expert"]') = 1;
```

**Middleware behavior:** Oracle's EXTRACTVALUE maps to MSSQL value(). Oracle's EXISTSNODE maps to MSSQL exist(). The XPath expressions are largely compatible between Oracle and MSSQL (both support XPath 1.0). The middleware also creates XML indexes on the target:
- Primary XML index on the XML column for all XQuery optimization.
- PATH secondary index for XPath expressions that start at the root.
- VALUE secondary index for value() extraction.
- PROPERTY secondary index for property retrieval.

**Performance delta:** With XML indexes, XQuery predicates can use index seeks rather than full XML document scans. The demonstration database's `HR.Employees.EmployeeData` column (XML data for 5,000 employees) benefits from these indexes for queries that filter by skill level (Operation 9).

#### Example 7: Flashback Query to Temporal Tables

**Oracle source:**
```sql
-- Point-in-time query (requires UNDO retention)
SELECT transaction_id, total_amount, status
FROM transactions
AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '7' DAY);
```

**MSSQL target:**
```sql
-- Point-in-time query using temporal table
SELECT TransactionID, TotalAmount, PaymentStatus
FROM Sales.Transactions
FOR SYSTEM_TIME AS OF DATEADD(DAY, -7, SYSUTCDATETIME());
```

**Middleware behavior:** The parser identifies the `AS OF TIMESTAMP` clause as a temporal query. The IR phase creates a temporal scan node with the timestamp expression. The optimization phase converts Oracle's `SYSTIMESTAMP - INTERVAL '7' DAY` to MSSQL's `DATEADD(DAY, -7, SYSUTCDATETIME())`. The code generation phase wraps the query with the `FOR SYSTEM_TIME AS OF` clause. The HIDDEN period columns (ValidFrom, ValidTo) are automatically excluded from the result set, matching Oracle's behavior (Flashback Query does not expose version metadata).

**Performance delta:** Oracle Flashback Query reads UNDO segments, which are stored in memory or on disk alongside the active data. The retention period is typically limited to a few hours (depending on UNDO_TABLESPACE size). MSSQL temporal tables maintain a separate history table with its own indexes, enabling point-in-time queries spanning years. For the demonstration database, the `Sales.TransactionsHistory` table grows automatically, and historical queries are supported for the full lifetime of the data.

---

## 5. Technology Stack

### 5.1 Core Components

**Language: TypeScript/Node.js (recommended)**

The middleware core should be implemented in TypeScript/Node.js for the following reasons:
- The `tedious` npm package provides a mature, well-maintained TDS (Tabular Data Stream) client for connecting to MSSQL. This eliminates the need to implement TDS protocol handling.
- Apache Calcite has a Node.js binding available through the `calcite` community project, though the primary Calcite implementation is Java. An alternative approach is to run Calcite as a Java microservice (using Calcite's JSON/HTTP API) and communicate with it from the Node.js middleware via HTTP.
- Node.js's asynchronous I/O model is well-suited for a proxy/middleware that must handle many concurrent connections without blocking.
- The TypeScript type system provides compile-time safety for the complex data structures involved in AST and IR manipulation.
- The npm ecosystem provides libraries for protocol parsing, netowrking, and object storage interaction (MinIO JavaScript Client).

**Alternative: Python** would provide access to Apache Calcite's Java API via JPype or Pyjnius, strong SQL parsing libraries (sqlparse, sqlglot), and the PyODBC library for MSSQL connectivity. However, Python's threading model (GIL) is less suited for high-concurrency proxy workloads.

**Alternative: Java** would provide native access to Apache Calcite (since Calcite itself is Java) and the JDBC API for MSSQL connectivity. However, the middleware does not need the full Java EE stack, and the deployment complexity of a Java application is higher than a Node.js application.

**Decision needed:** The final language choice should be made in Phase 0 based on prototype performance benchmarks with the Calcite integration layer.

**IR Engine: Apache Calcite**

Apache Calcite is the industry-standard open-source framework for SQL parsing and optimization. It provides:
- SQL parsers for multiple dialects (Oracle, MySQL, PostgreSQL, MSSQL, etc.) that produce a canonical AST.
- Relational algebra representation (RelNode tree) as the database-agnostic intermediate representation.
- Built-in optimization rules (predicate pushdown, join reordering, projection pruning, subquery unnesting).
- Cost-based optimizer with configurable statistics.
- Extensibility for custom optimization rules.

Calcite's Oracle parser handles most Oracle-specific syntax (CONNECT BY, DECODE, NVL, ROWNUM, DUAL), reducing the amount of custom parsing the middleware must implement. The middleware extends Calcite with custom rules for Oracle-to-MSSQL semantic conversions (CONNECT BY to HIERARCHYID, VPD to RLS, etc.).

**Protocol Layer:**

- **Incoming (TNS):** Custom TNS server implementation. This is the highest-risk component. The middleware must implement enough of the TNS protocol to accept connections from standard Oracle JDBC drivers. Reference: the TNS protocol specification (available in Oracle Net Services documentation) and Babelfish for PostgreSQL's implementation (which implements a subset of TDS).
- **Outgoing (MSSQL):** The `tedious` npm package for Node.js or `pyodbc` for Python. This encapsulates TDS protocol handling and provides a high-level API for executing SQL and retrieving results.

**Target Database: MSSQL 2022 Developer (Docker)**

The current PoC target is MSSQL 2022 Developer Edition running in a Docker container. Developer Edition is feature-complete with Enterprise Edition (including all In-Memory OLTP, columnstore, and advanced security features) and is free for non-production use. The docker-compose.yml in the repository configures the container with the following settings:
- Image: `mcr.microsoft.com/mssql/server:2022-latest`
- Port: 1433 (standard MSSQL port)
- Authentication: SQL Login (sa / YourStrong@Passw0rd)
- Volumes: persistent data, log, and secrets volumes
- Health check: sqlcmd-based readiness probe

### 5.2 Infrastructure

**Docker Compose:**

The current docker-compose.yml deploys a single MSSQL container. The production DataMigrata stack will extend this to include:

```yaml
version: '3.8'
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: mssql-advanced-demo
    ports:
      - "1433:1433"
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "YourStrong@Passw0rd"
      MSSQL_PID: "Developer"
      MSSQL_AGENT_ENABLED: "true"
    volumes:
      - mssql_data:/var/opt/mssql
      - mssql_log:/var/opt/mssql/log
      - mssql_secrets:/var/opt/mssql/secrets
    healthcheck:
      test: ["CMD", "/opt/mssql-tools/bin/sqlcmd", "-S", "localhost", "-U", "sa", "-P", "YourStrong@Passw0rd", "-Q", "SELECT 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  minio:
    image: minio/minio:latest
    container_name: minio-datamigrata
    ports:
      - "9000:9000"  # API
      - "9001:9001"  # Console
    environment:
      MINIO_ROOT_USER: "minioadmin"
      MINIO_ROOT_PASSWORD: "minioadmin123"
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 30s
      timeout: 10s
      retries: 3

  middleware:
    build: ./middleware
    container_name: datamigrata-middleware
    ports:
      - "1521:1521"  # TNS listener port (Oracle-compatible)
    environment:
      MSSQL_HOST: "mssql"
      MSSQL_PORT: "1433"
      MSSQL_USER: "sa"
      MSSQL_PASSWORD: "YourStrong@Passw0rd"
      MINIO_ENDPOINT: "minio:9000"
      MINIO_ACCESS_KEY: "minioadmin"
      MINIO_SECRET_KEY: "minioadmin123"
    depends_on:
      mssql:
        condition: service_healthy
      minio:
        condition: service_healthy
```

**Codespace Setup:**

The `tools/` directory in the repository provides everything needed for remote development via GitHub Codespaces:
- `tools/bin/gh` -- GitHub CLI binary (v2.63.2, static Linux x86_64) for SSH transport via `--stdio` mode.
- `tools/codespace_ssh.py` -- Python script using paramiko to execute commands on the codespace via the gh SSH transport.
- `tools/setup.py` -- Bootstrap script that installs paramiko, authenticates the gh CLI, and starts the codespace if needed.

This enables headless development from an AI agent or CI pipeline: the agent can SSH into the codespace, run docker-compose commands, execute SQL scripts, and verify results without requiring a desktop environment.

### 5.3 Open Questions and Decisions Needed

**Language choice for the middleware core:** TypeScript/Node.js is recommended for the reasons outlined in Section 5.1, but a Java implementation would provide native Calcite integration. The decision should be based on Phase 0 prototyping results. If the Calcite-as-HTTP-service approach works well, Node.js is viable. If the latency overhead is too high, Java may be necessary.

**TNS protocol implementation approach:** The TNS protocol is proprietary and partially undocumented. Three options exist:
1. **Full TNS implementation:** Reverse-engineer the protocol from packet captures and implement a complete TNS server. This is the most ambitious approach and carries the highest risk.
2. **Babelfish reference:** Study Babelfish for PostgreSQL's TDS implementation (which implements TDS for PostgreSQL, not TNS) as a reference for protocol-level proxy design. Babelfish does not implement TNS, but its architecture for wire-level compatibility is instructive.
3. **Oracle driver wrapper:** Instead of implementing TNS, modify the application's Oracle driver configuration to point to the middleware's endpoint, where a lightweight protocol adapter translates TNS frames to internal API calls. This requires the least protocol knowledge but may limit compatibility.

**Stored procedure translation strategy:** Two approaches for translating complex PL/SQL:
1. **Rule-based translation:** Define pattern-matching rules for common PL/SQL constructs (loops, cursors, exceptions, package variables). This works well for simple-to-moderate complexity but fails on creative or idiosyncratic code.
2. **LLM-assisted translation:** Use a large language model to translate PL/SQL blocks to T-SQL when rule-based translation cannot handle them. The LLM output is validated by running both the original PL/SQL (on Oracle) and the generated T-SQL (on MSSQL) with the same inputs and comparing results.
3. **Hybrid approach (recommended):** Start with rule-based translation for the most common patterns (which cover ~80% of enterprise PL/SQL code). Fall back to LLM-assisted translation for the remaining ~20%. Validate all translations with automated testing.

**Connection pooling strategy:** The middleware manages two connection pools: one for incoming connections (from Oracle applications) and one for outgoing connections (to MSSQL). The incoming pool is configured based on expected application concurrency (default: 100 connections). The outgoing pool is configured based on MSSQL connection limits (default: 50 connections, with multiplexing). The middleware must handle session affinity: an application session's transaction state, temp tables, and session context must be preserved across multiple connections to MSSQL.

**Concurrency model:** The middleware uses an event-driven architecture (Node.js event loop or Java virtual threads) to handle many concurrent client connections with minimal thread overhead. Each client connection is represented by a state machine that tracks the session state (connected, authenticated, in-transaction, etc.). The state machine processes TNS frames sequentially within a connection but processes multiple connections concurrently.

---

## 6. Implementation Roadmap

### 6.1 Phase 0: Foundation (Weeks 1-2)

**Objective:** Establish the development environment and validate that all 50 MSSQL operations execute correctly on the existing Docker instance.

**Tasks:**
- Clone the repository and verify the Docker Compose MSSQL instance starts correctly.
- Execute `sql/00_COMPLETE_MSSQL_Deployment.sql` to create the database schema and populate ~20,000 rows.
- Execute `sql/02_MSSQL_50_Operations_Expanded.sql` to verify all 50 operations return valid results.
- Set up the MinIO Docker container and verify S3-compatible API access.
- Create the middleware project structure (TypeScript or Java, to be decided).
- Set up VS Code development environment with MSSQL extension.
- Document any operations that fail or produce unexpected results.

**Deliverables:** Running MSSQL instance with demonstration data, verified 50-operation execution log, MinIO container operational, project skeleton with CI pipeline.

### 6.2 Phase 1: PoC -- Single Query Translation (Weeks 3-6)

**Objective:** Demonstrate end-to-end translation of a single Oracle SQL query to T-SQL, execution on MSSQL, and result verification.

**Tasks:**
- Integrate Apache Calcite into the middleware project (as a Java microservice or embedded dependency).
- Implement the Oracle SQL parser using Calcite's OracleParser.
- Implement the RelNode-to-T-SQL code generator.
- Select 5 representative queries from the 50 operations (one from each major category):
  1. A CONNECT BY query (Category 1)
  2. An XML query with value() and exist() (Category 2)
  3. A JSON query with OPENJSON (Category 3)
  4. A temporal AS OF query (Category 4)
  5. An indexed view query (Category 5)
- For each query: parse the Oracle syntax, generate T-SQL, execute on MSSQL, compare results with expected Oracle output.
- Implement the schema mapping registry (maps Oracle table/column names to MSSQL equivalents).

**Deliverables:** Working end-to-end translation pipeline for 5 queries, automated test harness comparing Oracle-expected results with MSSQL-actual results.

### 6.3 Phase 2: Protocol Layer (Weeks 7-12)

**Objective:** Implement the TNS protocol server that accepts connections from Oracle database drivers.

**Tasks:**
- Study TNS protocol specification and capture sample TNS packet sequences from an Oracle client connecting to an Oracle listener.
- Implement the TNS listener: accept TCP connections on port 1521.
- Implement the TNS handshake: respond to Oracle Net Services connect packet with accept packet.
- Implement basic authentication: handle username/password authentication over TNS.
- Implement SQL submission: receive SQL text in TNS data frames.
- Implement result set delivery: format MSSQL query results as TNS result set frames.
- Implement basic transaction control: COMMIT and ROLLBACK over TNS.
- Implement error delivery: map MSSQL error codes to Oracle error codes.
- Connect the protocol layer to the translation pipeline from Phase 1.

**Deliverables:** Oracle JDBC driver can connect to the middleware, issue a SQL query, and receive results. Basic transaction support.

### 6.4 Phase 3: Schema Translation Engine (Weeks 13-18)

**Objective:** Translate the full Oracle schema to an optimized MSSQL schema, migrate data, and populate all MSSQL features.

**Tasks:**
- Build the schema extraction module: connect to an Oracle instance (or read Oracle schema DDL files) and extract table definitions, column types, constraints, indexes, and Oracle-specific features.
- Implement the DDL translation engine: convert Oracle CREATE TABLE statements to MSSQL CREATE TABLE statements with optimized data types, computed columns, temporal versioning, and memory optimization.
- Implement the data type mapping: NUMBER -> DECIMAL/INT, VARCHAR2 -> NVARCHAR, DATE -> DATE/DATETIME2, CLOB -> NVARCHAR(MAX), BLOB -> VARBINARY(MAX), XMLType -> XML, SDO_GEOMETRY -> Geography/Geometry, etc.
- Implement the index creation strategy: map Oracle indexes to MSSQL indexes (bitmap -> columnstore, B-tree -> clustered/nonclustered, spatial -> GEOGRAPHY_GRID).
- Implement data migration: bulk-copy data from Oracle tables to MSSQL tables with type conversion.
- Create the HIERARCHYID representation from the adjacency list (populate `HR.OrgChart` from `HR.Employees.ManagerID`).
- Create XML Schema Collections from Oracle registered schemas.
- Set up encryption infrastructure: master key, certificates, symmetric keys.
- Configure Row-Level Security policies from Oracle VPD definitions.
- Implement the schema mapping registry: record every Oracle entity and its MSSQL equivalent.

**Deliverables:** Fully populated MSSQL database with optimized schema, all 12 tables migrated from Oracle source format, all MSSQL features configured.

### 6.5 Phase 4: Stored Procedure Translation (Weeks 19-26)

**Objective:** Translate Oracle PL/SQL stored procedures and packages to MSSQL T-SQL.

**Tasks:**
- Build the rule-based translation engine for common PL/SQL patterns:
  - DECODE -> CASE WHEN
  - CURSOR FOR loop -> WHILE with FETCH
  - EXCEPTION WHEN -> TRY...CATCH
  - DBMS_OUTPUT.PUT_LINE -> PRINT / RAISERROR
  - Package procedures -> Schema-qualified stored procedures
  - Package functions -> Scalar user-defined functions
  - Package variables -> SESSION_CONTEXT or temp table
- Implement the automated test harness: execute the same procedure on Oracle and MSSQL with identical inputs, compare outputs.
- Identify PL/SQL patterns that cannot be handled by rules.
- Integrate LLM-assisted translation for complex procedures (if chosen).
- Validate all translated procedures against the test harness.
- Translate the demonstration database's stored procedures (usp_GetCustomerCache, usp_BulkInsertOrders, usp_GetSensitiveEmployeeData).

**Deliverables:** Rule-based translation engine covering ~80% of common PL/SQL patterns, automated test harness with comparison results, LLM-assisted translation for edge cases (if applicable).

### 6.6 Phase 5: Optimization (Weeks 27-32)

**Objective:** Optimize query performance on the MSSQL target using columnstore, in-memory OLTP, and MinIO integration.

**Tasks:**
- Implement query plan analysis: capture MSSQL execution plans for translated queries and compare with Oracle execution plans.
- Apply columnstore optimization: identify analytical queries that benefit from columnstore indexes and ensure the translation generates queries that use batch mode.
- Apply in-memory OLTP optimization: identify hot-path tables and queries, migrate to memory-optimized tables with hash indexes.
- Implement MinIO integration: build the data classification engine, configure MinIO buckets (xmldata, jsondata, lobdata, auditlogs), implement blob read/write redirect.
- Configure Query Store: enable Query Store on the MSSQL database to capture query performance metrics over time.
- Run performance benchmarks: compare query response times between Oracle source and MSSQL target for all 50 operations.
- Tune the translation pipeline: add optimization rules that improve MSSQL execution plans (index hints, query hints, columnstore-appropriate query structures).

**Deliverables:** Performance benchmark report, MinIO integration operational, columnstore and in-memory optimizations applied, Query Store configured.

### 6.7 Phase 6: Production Readiness (Weeks 33-40)

**Objective:** Make the middleware production-ready with proper error handling, monitoring, and documentation.

**Tasks:**
- Implement comprehensive error handling: translate MSSQL errors to Oracle error codes, handle connection failures gracefully, implement retry logic for transient errors.
- Implement logging and monitoring: structured logging (JSON format), metrics export (Prometheus format), health check endpoints.
- Implement connection pooling: configure incoming connection pool, outgoing MSSQL connection pool, session state management, multiplexing.
- Implement failover and recovery: connection retry with exponential backoff, transaction rollback on connection failure, state reconstruction after reconnect.
- Implement security: TLS for all connections (TNS over TLS, MSSQL encrypted connection), authentication validation, authorization checks.
- Write documentation: API documentation, configuration guide, deployment guide, troubleshooting guide.
- Write the complete test suite: unit tests for each translation rule, integration tests for each of the 50 operations, end-to-end tests for the full middleware pipeline.

**Deliverables:** Production-ready middleware with error handling, monitoring, connection pooling, failover, security, and documentation.

---

## 7. Dev Environment Setup

### 7.1 Local Development with Docker

The development environment uses Docker Compose to deploy the MSSQL instance. Setup takes approximately 5 minutes:

```bash
# Clone the repository
git clone https://github.com/topic-hash/DataMigrata.git
cd DataMigrata

# Start the MSSQL container
cd docker
docker-compose up -d
cd ..

# Wait 30 seconds for initialization
sleep 30

# Verify the container is running
docker ps
```

### 7.2 VS Code with MSSQL Extension

Visual Studio Code with the MSSQL extension replaces the retired Azure Data Studio as the recommended database tool:

1. Download VS Code from https://code.visualstudio.com/download
2. Open Extensions view (Ctrl+Shift+X)
3. Search "mssql" and install "SQL Server (mssql)" by Microsoft
4. Press F1, select "MS SQL: Manage Connection Profile"
5. Configure: Server: `localhost,1433`, Authentication: SQL Login, User: `sa`, Password: `YourStrong@Passw0rd`

### 7.3 Database Deployment

Open `sql/00_COMPLETE_MSSQL_Deployment.sql` in VS Code and execute with Ctrl+Shift+E. This creates the database with all 12 tables, ~20,000 rows of synthetic data, and all enterprise features (temporal tables, encryption, RLS, data masking, spatial indexes, columnstore, partitioning).

### 7.4 Executing the 50 Operations

Open `sql/02_MSSQL_50_Operations_Expanded.sql` in VS Code and execute category by category. Each category is separated by a header comment. The operations build on the deployed data and demonstrate all MSSQL capabilities that the middleware must translate.

### 7.5 Remote Codespace Access

For headless development (AI agents, CI pipelines), use the tools in the `tools/` directory:

```bash
# Bootstrap (one-time)
python3 tools/setup.py --token ghp_YOUR_TOKEN

# Execute commands on the codespace
python3 tools/codespace_ssh.py \
  --token ghp_YOUR_TOKEN \
  --codespace symmetrical-tribble \
  --command "cd /workspaces/DataMigrata/docker && docker compose up -d && docker compose ps"
```

### 7.6 MinIO Setup

```bash
# Start MinIO container
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v minio_data:/data \
  --name minio-datamigrata \
  minio/minio server /data --console-address ":9001"

# Create buckets
docker exec minio-datamigrata mc alias set local http://localhost:9000 minioadmin minioadmin123
docker exec minio-datamigrata mc mb local/xmldata
docker exec minio-datamigrata mc mb local/jsondata
docker exec minio-datamigrata mc mb local/lobdata
docker exec minio-datamigrata mc mb local/auditlogs
```

---

## 8. Risk Register

### 8.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **TNS protocol incompatibility:** The middleware's TNS implementation may not support all Oracle driver behaviors (advanced authentication, LOB streaming, cursor types, array binding). | High | Critical | Implement TNS incrementally, starting with the most common driver operations. Maintain a compatibility matrix of supported operations. Use packet capture from real Oracle connections to validate behavior. |
| **Stored procedure translation completeness:** PL/SQL is Turing-complete. Some procedures may use Oracle-specific packages (UTL_HTTP, DBMS_SCHEDULER, etc.) that have no MSSQL equivalent. | High | High | Prioritize common patterns. Flag unsupported operations clearly. Consider CLR integration for complex logic that cannot be translated. |
| **Performance regression:** The middleware adds latency (parsing, translation, execution) that may offset MSSQL's performance advantages for simple queries. | Medium | High | Profile each pipeline phase. Cache parsed ASTs for frequently repeated queries (prepared statement optimization). Pre-translate known queries at schema migration time. |
| **Calcite dialect coverage:** Calcite's Oracle parser may not handle all Oracle SQL extensions, especially newer features (JSON in 12c, polymorphic table functions in 19c). | Medium | Medium | Extend Calcite's Oracle parser with custom syntax rules for unsupported constructs. Contribute parser extensions back to Calcite if possible. |
| **Semantic equivalence:** Some Oracle operations have subtly different semantics from their MSSQL equivalents (NULL handling in aggregations, date arithmetic edge cases, case sensitivity). | Medium | Medium | Build a comprehensive test suite comparing Oracle and MSSQL results for edge cases. Document known semantic differences. |

### 8.2 Scope Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Oracle feature coverage:** Enterprise Oracle databases use features beyond the 50 defined operations (Advanced Queuing, Workspace Manager, Edition-Based Redefinition, etc.). | High | High | Phase the implementation: cover the 50 operations first, then expand. Prioritize features used by the target application workload. |
| **PL/SQL package complexity:** Large enterprise Oracle databases may have hundreds of PL/SQL packages with thousands of procedures, many containing undocumented business logic. | High | High | Use automated schema extraction to enumerate all PL/SQL objects. Prioritize translation by usage frequency (captured via workload analysis). |
| **Data volume at scale:** The demonstration database has ~20,000 rows. Production databases may have billions of rows, requiring different migration strategies and optimization approaches. | Medium | High | Design the migration pipeline for bulk operations (BCP, SSIS, or custom bulk-copy). Test with progressively larger datasets. |
| **MinIO latency for LOB operations:** Redirecting LOB reads/writes through MinIO adds network hops that may be slower than direct database reads. | Medium | Medium | Benchmark MinIO latency vs. native MSSQL VARBINARY(MAX) storage. Set size thresholds based on benchmark results. Consider SSD-backed MinIO storage for performance-critical LOBs. |

### 8.3 Lessons From ERP Migration Failures

The "Beyond the Black Box" analysis documents 10 real ERP migration failures. The common failure patterns that DataMigrata must avoid:

1. **Birmingham City Council (2020, 100M GBP):** Naive migration without testing under realistic workload. DataMigrata mitigates this by validating against all 50 operations before deploying.
2. **Revlon (supply chain collapse):** Migration broke critical business processes. DataMigrata mitigates this by maintaining application compatibility through the middleware layer.
3. **Lidl (project abandonment):** Scope creep and underestimated complexity of stored procedure translation. DataMigrata mitigates this by phasing implementation and starting with a PoC.
4. **Hertz (post-bankruptcy):** Data integrity loss during migration. DataMigrata mitigates this by using bidirectional transformation with semantic mapping, not 1:1 copying.
5. **General pattern: underestimated testing.** DataMigrata mitigates this by building an automated test harness that compares Oracle and MSSQL results for every translated operation.

---

## 9. References

### 9.1 Core Technologies

- **Apache Calcite:** https://calcite.apache.org -- SQL parser, optimizer, and relational algebra framework. The IR engine at the core of the DataMigrata pipeline.
- **Apache Calcite Oracle Parser:** https://calcite.apache.org/docs/reference.html -- Oracle SQL dialect support in Calcite.
- **MSSQL 2022 Documentation:** https://docs.microsoft.com/sql -- Reference for all MSSQL features used by the middleware (HIERARCHYID, temporal tables, in-memory OLTP, columnstore, spatial, encryption, RLS).

### 9.2 Protocol Specifications

- **TDS Protocol (Tabular Data Stream):** https://docs.microsoft.com/openspecs/windows_protocols/ms-tds -- Microsoft's wire protocol for SQL Server. Used by the middleware's MSSQL driver.
- **TNS Protocol (Transparent Network Substrate):** Oracle Net Services documentation (proprietary). The middleware must implement a subset of this protocol.
- **Babelfish for PostgreSQL:** https://babelfishforpostgresql.org/ -- AWS's implementation of TDS wire protocol for PostgreSQL. A useful reference for protocol-level proxy design, though Babelfish implements TDS (not TNS) and targets PostgreSQL (not MSSQL).

### 9.3 Migration Tools (Reference Implementations)

- **SQL Server Migration Assistant (SSMA) for Oracle:** https://aka.ms/ssma-oracle -- Microsoft's official tool for Oracle-to-MSSQL schema and data migration. DataMigrata's schema translation engine uses SSMA's mapping rules as a reference but goes further by optimizing the target structure.
- **Ora2Pg:** https://ora2pg.darold.net/ -- Open-source Oracle-to-PostgreSQL migration tool. Useful as a reference for PL/SQL translation patterns, though DataMigrata targets MSSQL.
- **AWS Schema Conversion Tool (SCT):** https://aws.amazon.com/database/schema-conversion-tool/ -- AWS's tool for heterogeneous database migration. Useful as a reference for automated schema analysis.

### 9.4 Repository Files

- **PROJECT_PLAN.md:** `/docs/PROJECT_PLAN.md` -- Architecture decisions, Oracle-to-MSSQL mapping table, database schema overview, development roadmap.
- **00_COMPLETE_MSSQL_Deployment.sql:** `/sql/00_COMPLETE_MSSQL_Deployment.sql` -- Complete idempotent database creation script (12 tables, ~20,000 rows, all enterprise features).
- **02_MSSQL_50_Operations_Expanded.sql:** `/sql/02_MSSQL_50_Operations_Expanded.sql` -- All 50 sophisticated MSSQL operations organized by category.
- **docker-compose.yml:** `/docker/docker-compose.yml` -- MSSQL Docker container configuration.
- **SETUP.md:** `/SETUP.md` -- Development environment setup guide and codespace remote access instructions.

### 9.5 Foundational Analysis

- **"Beyond the Black Box":** The foundational analysis document that describes the compiler-based architecture (parsing, AST, IR, code generation), protocol emulation, session state management, polyglot persistence, and ERP migration failure patterns. This document is the intellectual ancestor of the DataMigrata specification.
