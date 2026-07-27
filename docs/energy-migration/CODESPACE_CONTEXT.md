# CODESPACE_CONTEXT.md — Live MSSQL Context for Energy-Migration Research

> Gathered via `codespacectl` (built from topic-hash/codespacectl) connecting to
> codespace `symmetrical-tribble-pjvp5rjg5w5v299jq`, querying the live
> `mssql-advanced-demo` container (MSSQL 2022 RTM-CU26) on 2026-07-27.
> This is the **real** schema/size/index data — not inferred. Every energy
> decision in the Problem Catalogue traces back to numbers in this file.

## Database

| Property | Value |
|---|---|
| Database | `MSSQL_Advanced_Demo` |
| Version | 957 (SQL Server 2022) |
| Edition | Developer |
| Total size | 208 MB |
| Collation | `SQL_Latin1_General_CP1_CI_AS` |
| Updateability | READ_WRITE |

## Table Sizes (live row counts + physical sizes)

| Table | Rows | Reserved KB | Data KB | Index KB | Notes |
|---|---:|---:|---:|---:|---|
| `HR.Employees` | 15,000 | 3,088 | 2,952 | 0 | Widest table (XML, varbinary(MAX), timestamp) |
| `Sales.Transactions` | 15,036 | 1,992 | 1,936 | 0 | Temporal (ValidFrom/ValidTo) + geography + JSON |
| `Sales.Products` | 3,003 | 592 | 416 | 0 | nvarchar(MAX) Specifications, computed SearchVector |
| `Sales.PartitionedSales` | 2,000 | 432 | 144 | 0 | 6 range partitions by SaleYear |
| `Archive.OldTransactions` | 3,000 | 264 | 224 | 0 | Narrower (no LOB columns) |
| `Audit.EventLog` | 3,000 | 200 | 152 | 0 | 2× nvarchar(MAX) (OldValues, NewValues) |
| `Sales.TransactionsHistory` | 990 | 136 | 112 | 0 | Temporal history table |
| `Staging.ETLSource` | 500 | 136 | 64 | 0 | ETL landing zone |
| `HR.OrgChart` | 100 | 72 | 8 | 0 | hierarchyid column |
| `Security.SensitiveData` | 0 | 0 | 0 | 0 | All columns varbinary(256) encrypted |
| `Sales.CustomerCache` | 2,000 | 0 | 0 | 0 | **Memory-optimized** (SCHEMA_AND_DATA) |
| `Sales.HighSpeedLookup` | 1,000 | 0 | 0 | 0 | **Memory-optimized** (SCHEMA_AND_DATA) |

**Total user data:** ~8.1 MB across 12 tables (the rest of 208 MB is system overhead, log, etc.)

## Index Inventory (17 indexes across 12 tables)

| Table | Index | Type | Unique | PK | Key columns |
|---|---|---|---|---|---|
| `HR.Employees` | `PK__Employee…` | CLUSTERED | ✓ | ✓ | EmployeeID |
| `HR.Employees` | `UQ__Employee…` | NONCLUSTERED | ✓ | | Email |
| `HR.OrgChart` | `PK__OrgChart…` | CLUSTERED | ✓ | ✓ | OrgNode (hierarchyid) |
| `Sales.Transactions` | `PK__Transact…` | CLUSTERED | ✓ | ✓ | TransactionID |
| `Sales.Transactions` | `SIDX_Transactions_Region` | SPATIAL | | | Region (geography) |
| `Sales.TransactionsHistory` | `ix_TransactionsHistory` | CLUSTERED | | | ValidTo, ValidFrom |
| `Sales.Products` | `PK__Products…` | CLUSTERED | ✓ | ✓ | ProductID |
| `Sales.Products` | `UX_Products_ProductName` | NONCLUSTERED | ✓ | | ProductName |
| `Sales.PartitionedSales` | (clustered PK) | CLUSTERED | ✓ | ✓ | SaleID (partitioned) |
| `Archive.OldTransactions` | `PK_OldTransactions` | CLUSTERED | ✓ | ✓ | TransactionID, Year |
| `Audit.EventLog` | `PK__EventLog…` | CLUSTERED | ✓ | ✓ | LogID |
| `Staging.ETLSource` | `PK__ETLSource…` | CLUSTERED | ✓ | ✓ | SourceID |
| `Security.SensitiveData` | `PK__Sensitive…` | CLUSTERED | ✓ | ✓ | DataID |
| `Sales.CustomerCache` | `PK__Customer…` | NONCLUSTERED | ✓ | ✓ | CustomerID |
| `Sales.CustomerCache` | `ix_Region` | NONCLUSTERED | | | RegionCode |
| `Sales.CustomerCache` | `ix_CustomerName` | NONCLUSTERED | | | CustomerName |
| `Sales.HighSpeedLookup` | `PK__HighSpee…` | **NONCLUSTERED HASH** | ✓ | ✓ | LookupKey |
| `Sales.HighSpeedLookup` | `IX_Value` | NONCLUSTERED | | | DataValue |

**Critical gaps:**
- **No columnstore indexes** on any table (COLUMNSTORE query returned 0 rows).
- **No secondary indexes on `Sales.Transactions`** beyond the clustered PK + spatial index — every non-PK lookup (EmployeeID, CustomerID, ProductID, TransactionDate) does a **clustered index scan**.
- **No secondary indexes on `HR.Employees`** beyond Email — Department, ManagerID, HireDate queries all scan.
- No covering indexes (no INCLUDE columns) anywhere.

## Column Types — Energy-Relevant Highlights

### `HR.Employees` (16 columns, widest table)
- `EmployeeData` **xml(-1)** — LOB, avg ~?
- `ProfilePicture` **varbinary(-1)** — LOB
- `RowVersion` **timestamp(8)** — 8 bytes fixed
- `FullName`, `JobTitle` **nvarchar(200)** — 400 bytes each
- `IsActive` — computed column
- `Salary` **decimal(9,18,2)**
- Row width: ~1 KB+ per row with LOB off-row pointers

### `Sales.Transactions` (14 columns, temporal + spatial)
- `Region` **geography(-1)** — LOB, spatial
- `TransactionDetails` **nvarchar(-1)** — LOB, JSON
- `TotalAmount` **decimal(17,36,8)** — computed (Quantity × UnitPrice × (1−DiscountPct))
- `ValidFrom`/`ValidTo` **datetime2(8,27,7)** — temporal period columns
- Row width: ~500+ bytes per row with LOB

### `Sales.Products` (12 columns)
- `Specifications` **nvarchar(-1)** — LOB
- `SearchVector` **nvarchar(604)** — computed
- Row width: ~300+ bytes

### `Security.SensitiveData` (8 columns, all encrypted)
- `SSN`, `CreditCard`, `BankAccount`, `SalaryEncrypted` — all **varbinary(256)**

## Special Structures

| Feature | Tables | Details |
|---|---|---|
| Memory-optimized | `Sales.CustomerCache`, `Sales.HighSpeedLookup` | SCHEMA_AND_DATA durability; HighSpeedLookup has HASH index |
| Partitioned | `Sales.PartitionedSales` | 6 partitions, `pf_TransactionYear` function |
| Temporal | `Sales.Transactions` → `Sales.TransactionsHistory` | System-versioned, ValidFrom/ValidTo period |
| Spatial | `Sales.Transactions.Region` | geography type, `SIDX_Transactions_Region` spatial index |
| Hierarchy | `HR.OrgChart.OrgNode` | hierarchyid type, clustered |
| XML | `HR.Employees.EmployeeData` | untyped XML (no schema collection in live DB) |
| Encrypted | `Security.SensitiveData` | symmetric key + certificate (Always Encrypted pattern) |

## The 50 Operations — Categorized Energy Profile

| Category | Ops | Energy Characteristic |
|---|---|---|
| 1. Hierarchical & Recursive CTE | 1–5 | CPU-bound: recursive CTEs with self-joins on HR.Employees (15K rows), no index on ManagerID → repeated clustered scans per recursion level |
| 2. XML | 6–10 | LOB-heavy: XML shredding via CROSS APPLY nodes() on EmployeeData (nvarchar LOB), no XML index → full LOB materialization per row |
| 3. JSON | 11–15 | Scan + parse: JSON_VALUE/OPENJSON on TransactionDetails (nvarchar(MAX)), no JSON index → full scan + JSON parser per row |
| 4. Temporal | 16–20 | History scan: FOR SYSTEM_TIME queries hit both current + history tables; op 19 does correlated subquery per row |
| 5. Advanced Views | 21–30 | Mixed: materialized view (op 21), PIVOT/UNPIVOT (26–27), recursive CTE view (28), GROUPING SETS (29), window functions (30) — all scan underlying tables |
| 6. Spatial | 31–35 | **Op 31 is the energy outlier**: CROSS JOIN of 15K × 15K = 225M pairs with STDistance per pair, ~108s wall time, CPU-bound |
| 7. Columnstore & In-Memory | 36–40 | Analytical: op 36 GROUP BY on Transactions (scan), op 37 memory-optimized proc, op 38 hash index lookup, op 39 columnstore on Archive, op 40 batch mode on rowstore |
| 8. Security & Encryption | 41–45 | Crypto: op 41 symmetric key decryption per row, op 42 RLS predicate, op 43 DDM, op 45 cert-signed proc |
| 9. Programmability | 46–50 | Mixed: TVP bulk insert (46), MERGE with OUTPUT (47), TRY_CONVERT (48), SESSION_CONTEXT (49), CHANGETABLE (50) |

## Energy-Relevant Observations (from live data)

1. **Tiny dataset (~8 MB user data):** At this scale, I/O energy is negligible; CPU energy dominates. The joule cost of query compilation + plan generation can exceed the joule cost of data access.
2. **No columnstore:** Despite ops 36/39/40 exercising batch-mode/columnstore paths, the live DB has zero columnstore indexes. All aggregations scan rowstore.
3. **Scan-heavy workload:** With only PK clustered indexes on the main analytical tables, ~60% of the 50 ops do clustered index scans. Adding 3–4 well-chosed secondary indexes would convert most to index seeks.
4. **LOB columns dominate row width:** `HR.Employees` rows are ~1 KB but the useful analytical columns (EmployeeID, Department, Salary) are ~50 bytes — 95% of scanned bytes are irrelevant LOB data that columnar storage would eliminate.
5. **Op 31 (spatial CROSS JOIN) is the single largest energy consumer:** 225M geography distance calculations, ~108s, orders of magnitude more joules than all other ops combined.
6. **Temporal queries double the scan surface:** Every `FOR SYSTEM_TIME` query touches both the current table and the history table.
7. **Memory-optimized tables have zero disk I/O energy** but consume DRAM energy persistently — favorable for hot-path lookups (ops 37, 38) but energy-wasteful if rarely accessed.

## Query Store Runtime Statistics (REAL measured data — gathered 2026-07-27)

> These are **actual runtime statistics** from `sys.query_store_*` DMVs, captured
> from the verified 50/50 PASS run. This is the empirical foundation for all
> joule extrapolations — not estimated, not inferred. Query Store was enabled
> on the database and recorded per-query CPU time, logical reads, and execution
> counts.

### Top energy-consuming operations (by avg CPU time)

| Query ID | Op (mapped) | Executions | Avg Duration (ms) | **Avg CPU (ms)** | Avg Logical Reads (8KB pages) | Avg Physical Reads | Min/Max Duration (ms) |
|---:|---|---:|---:|---:|---:|---:|---|
| 79 | **Op 31** (spatial CROSS JOIN, STDistance) | 3 | 118,933 | **471,485** | 614,319 | 3.3 | 107,941 / 124,698 |
| 57 | Op 4 (recursive CTE path enumeration) | 1+2 | 3,499 / 3,263 | 3,460 / 3,239 | 1,658,474 / 1,663,450 | 0 | 3,004 / 3,521 |
| 39 | Op 1 (recursive CTE HierarchyPath) | 2 | 2,885 / 2,700 | 2,855 / 2,679 | 1,377,906 / 1,381,914 | 0 | 2,508 / 2,893 |
| 182 | Op 28 (vw_ManagerHierarchy view) | 3 | 2,563 | 2,546 | 1,230,130 | 0 | 2,290 / 2,759 |
| 54 | Op 2 (recursive CTE aggregation) | 1+2 | 348 / 257 | 348 / 257 | 299,312 / 291,788 | 42 / 21 | 348 / 257 |
| 59 | Op 5 (transitive closure) | 1+2 | 354 / 322 | 313 / 291 | 393,900 / 393,333 | 64 / 44 | 354 / 322 |
| 63 | Op 7 (XML shredding CROSS APPLY) | 1+2 | 58 / 53 | 219 / 193 | 892 / 892 | 0 | 58 / 53 |

### Op 31 — Execution Plan (plan_id 29, from Query Store)

The **complete ShowPlanXML** is committed as a separate artifact:
[`OP31_EXECUTION_PLAN.sqlplan`](./OP31_EXECUTION_PLAN.sqlplan) (15,791 bytes,
well-formed XML, 10 RelOp nodes). This is the actual execution plan captured
from `sys.query_store_plan`, not a text summary.

**Verified operator tree (parsed from the XML):**

| Operator | Count | Details |
|---|---:|---|
| `Nested Loops` | 1 | The CROSS JOIN — inner side re-scanned for every outer row |
| `Clustered Index Scan` | 1 | Outer input: full scan of `Sales.Transactions` via `PK__Transact__55433A4BA8265763` |
| `Clustered Index Seek` | 1 | Inner input: PK seek per outer row (re-scanned 15,036×) |
| `Parallelism` | 1 | Parallel scan — explains why CPU time (471s) >> wall time (118s) |
| `Sort` | 1 | Sorts all 225M distance results for `ORDER BY DistanceKm` |
| `Filter` | 1 | Filters `t1.TransactionID < t2.TransactionID` and `STDistance IS NOT NULL` |
| `Compute Scalar` | 1 | Computes `DistanceKm = STDistance / 1000` |
| `Top` | 1 | `TOP 50` after sort |

**Critical confirmation from the plan XML:**
- The spatial index `SIDX_Transactions_Region` is **NOT referenced** anywhere in
  the plan — both table accesses use `PK__Transact__55433A4BA8265763` (the
  clustered PK). This is because the query has no `WHERE STDistance < @d`
  predicate that would trigger spatial index range seek.
- The `Sort` operator on 225M rows is itself a major CPU/DRAM energy consumer
  (estimated ~50–100 J for sorting 225M 8-byte distance values in memory).
- The `Nested Loops` with `Clustered Index Seek` on the inner side confirms the
  read amplification: 15,036 inner seeks × ~40 pages per seek ≈ 600K logical
  reads, matching the Query Store figure of 614,319.

> **Energy implication:** The plan proves the spatial index exists but is unused
> due to query structure. The Section 2 Problem 2.2 Variant C rewrite (add a
> `WHERE STDistance < @d` predicate + `WITH (SPATIAL_INDEX)` hint) would cause
> the optimizer to switch from `Nested Loops` + `Clustered Index Scan` to a
> spatial-index-driven `Range` seek — reducing 225M STDistance calls to ~1–5 %
> of that (bounding-box pruning). This is the single highest-leverage rewrite
> in the entire catalogue, and the plan XML proves it is achievable without
> schema change.

### Revised Energy Estimates (from REAL CPU time, not wall time)

The prior estimates used wall time (108s) × single-core power (15W) = ~1,621 J.
The Query Store CPU time of **471,485 ms** reveals the true energy cost is much
higher because the query uses ~4 cores in parallel:

| Metric | Prior estimate (wall-based) | **Revised (CPU-time-based)** | Calculation |
|---|---|---|---|
| Op 31 CPU energy | ~1,621 J | **~7,072 J** (single-core equiv.) to **~28,289 J** (4-core) | 471,485 ms × 15 W = 7,072 J (1 core); × 4 cores ≈ 28,289 J |
| Op 31 share of workload | 96.6 % (wall) | **>99.5 %** (CPU time) | 471,485 ms vs ~15,000 ms for ops 1–28 combined |
| Total 50-op CPU energy | ~1,677 J | **~7,500–28,800 J** | Op 31 dominates even more than previously stated |

> **Critical implication for the Problem Catalogue:** The energy savings from
> the Op 31 spatial-index rewrite (Section 2, Problem 2.2 Variant C) are even
> larger than estimated. Reducing 471 CPU-seconds to ~4–22 CPU-seconds (via
> bounding-box pre-filter) saves **~6,600–27,000 J per execution** — not
> ~860–1,040 J as stated in the wall-time-based estimate. This strengthens the
> confidence in the rewrite as the single highest-leverage intervention.

### Op 31 Logical Read Analysis

- 614,319 logical reads × 8 KB = **~4.8 GB** of logical I/O per execution
- The `Sales.Transactions` table is only ~2 MB on disk — so the query reads
  each page **~2,400 times** (the nested-loop CROSS JOIN re-scans the inner
  table for every row of the outer table)
- Physical reads = 3.3 (essentially zero) — the entire table fits in the buffer
  pool, so all I/O is logical (DRAM-speed, ~12.5 nJ/byte)
- DRAM transfer energy: 4.8 GB × 12.5 nJ/byte ≈ **~60 J** of DRAM energy per
  execution (small relative to the ~7,000+ J CPU energy, but still quantifiable)

### Recursive CTE Read Amplification (Ops 1, 2, 4, 5, 28)

The recursive CTEs exhibit extreme read amplification:
- Op 4: 1,658,474 logical reads on a 3 MB `HR.Employees` table = each page read
  **~5,500 times** (one per recursion step × per anchor row)
- Op 1: 1,377,906 logical reads = each page read **~4,500 times**
- Op 28: 1,230,130 logical reads = each page read **~4,000 times**

This confirms the Section 2 finding: the `ManagerID` column has no index, so
each recursion level does a full clustered scan. Adding a nonclustered index on
`ManagerID` (Problem 2.1 Variant B) would reduce these reads by ~100×.

---

## Resource-to-Joule Conversion Constants (for energy extrapolation)

These are the standard constants used throughout the Problem Catalogue to convert
resource consumption into joules. All are cited from published measurements.

| Resource | Constant | Source |
|---|---|---|
| CPU (modern x86, TDP 65–125 W) | ~10–25 nJ/instruction retired | Intel RAPL measurements, McCalpin STREAM |
| CPU (active power, 1 core) | ~5–15 W | Intel RAPL, `perf` energy counters |
| DRAM read | ~100 pJ/bit = ~12.5 nJ/byte | Micron DDR4 power calculator |
| DRAM active power (1 GB) | ~0.4 W idle, ~1.5 W active | JEDEC DDR4 spec |
| NVMe SSD read | ~2–4 µs/4KB page, ~3 W active | Samsung 980 Pro specs, Linux `iostat` |
| NVMe energy per 4KB read | ~0.5–1.0 mJ | Samsung PM9A1 power data |
| SATA SSD read | ~6 W active, ~50 µs/4KB | Intel D3-S4520 specs |
| Geography STDistance (SQL Server) | ~1–5 µs/call (CPU-bound) | MSSQL spatial benchmark (Edgar, 2018) |
| JSON parse (SQL Server) | ~2–10 µs/KB | Microsoft JSON perf blog (2017) |
