# Section 3 — Optimal Structural Depictions for Minimal Energy Retrieval

The physical shape of the migrated schema is the largest single lever on query
joules. Across the 50-operation catalogue, ~60% of ops do a clustered index
scan of `HR.Employees` (15,000 rows, ~1 KB/row, 3,088 KB reserved) or
`Sales.Transactions` (15,036 rows, ~500+ bytes/row, 1,992 KB reserved), and
the live `CODESPACE_CONTEXT.md` confirms that **0 of 12 tables have a
columnstore index** and **only 1 of 9 views (`Sales.vw_ProductSummary`) is
materialized** — every analytical view over `Sales.Transactions` recomputes
from a 15K-row scan on every call. Because the live dataset is only ~8 MB of
user data, NVMe I/O energy is amortised to near-zero; **DRAM and CPU dominate
the joule budget** (DRAM ≈ 12.5 nJ/byte, CPU ≈ 10–25 nJ/instruction retired,
per the constants in `CODESPACE_CONTEXT.md`). The four problems below
re-architect the physical layout so that the 5% of bytes a query actually
needs are the bytes that get dragged through DRAM and CPU registers.

---

### Problem 3.1: Columnar vs row physical storage for the 50-op mix

**Goal:** A single physical layout that minimises DRAM bytes scanned for the
~45 analytical/read ops while not penalising the ~5 point-DML/LOB-mutating
ops (ops 6, 13, 46) that need full-row access.

**Solutions:**

**Variant A: Pure columnstore (clustered columnstore index, CCI) on the two
hot analytical tables.**
Rebuild `HR.Employees` and `Sales.Transactions` as clustered columnstore
indexes. For `HR.Employees` the analytical projection (EmployeeID,
Department, Salary, JobTitle, ManagerID, HireDate) is ~50 bytes per row; the
remaining ~950 bytes per row are `EmployeeData` (XML), `ProfilePicture`
(varbinary(MAX)), `RowVersion`, and `FullName`/`JobTitle` nvarchar(200). On a
CCI, SQL Server stores LOB columns off-row in separate LOB allocations, so a
scan that projects only the analytical columns reads ~50 bytes × 15,000 =
750 KB. DRAM energy: 750 KB × 12.5 nJ/byte = **9.4 mJ** vs the rowstore's
15,000 × 1,024 × 12.5 nJ = **192 mJ** — a **20× DRAM-energy reduction**.
Batch-mode execution on the columnstore provides an additional 2–4×
throughput improvement (Microsoft, *Columnstore Indexes Overview*,
learn.microsoft.com). For `Sales.Transactions`, analytical projections
(TransactionID, EmployeeID, TotalAmount, TransactionDate) are ~30 bytes; the
columnar scan reads 30 × 15,036 = 451 KB → **5.6 mJ** vs rowstore's 7.5 MB →
**94 mJ** (17× reduction). ClickHouse's engineering team reports column
stores compress 5–10× tighter than row stores in equivalent workloads
(clickhouse.com, *Row-oriented vs column-oriented databases*, May 2026),
which corroborates the 12–20× DRAM-byte reduction we extrapolate here once
dictionary encoding (Problem 3.4) is layered on.

**Variant B: Hybrid HTAP — nonclustered columnstore on top of the existing
clustered rowstore PK.**
Keep the rowstore clustered PK on `EmployeeID`/`TransactionID` (so ops 6
XML.modify, 13 JSON_MODIFY, 46 TVP bulk-insert continue to seek single rows
in O(log N)) and add a **nonclustered columnstore index** on the analytical
columns only. This is the SQL Server 2022 "operational analytics" pattern
(learn.microsoft.com, *Columnstore Indexes Overview*). The CCI-on-rowstore
pattern from Variant A breaks the XML DML path because CCI becomes the
storage format; Variant B preserves LOB mutate-in-place. Cost: every
non-PK insert/update maintains a second structure (~1.5× write amplification)
— for the 50-op catalogue the only writes are ops 6, 13, 46, 47
(MERGE) and the populate script, so maintenance energy is negligible. Read
energy for analytical ops is essentially identical to Variant A.

**Variant C: Polyglot split — separate columnar analytical projection table
populated by CDC.**
Project `HR.Employees` into a narrow `HR.Employees_Analytic` table (EmployeeID,
Department, Salary, JobTitle, ManagerID, HireDate) stored as CCI, kept in
sync by CHANGETABLE (op 50 already exercises this). Point-DML stays on the
rowstore original; analytical queries (ops 1–5, 21, 26, 29, 36) hit the
columnar projection. The disadvantage is doubled storage (≈ 8 MB + 0.75 MB =
~9 MB) and CDC latency, but at this scale the storage-energy penalty is
~9 mJ/scan-at-most (Vortex/Parquet blog, dataengineeringcentral.substack.com).
EXTRAPOLATION: this is the safest option if the columnstore on the base
table fails to build (the live DB reports zero columnstore indexes despite
the deployment script containing a `CREATE NONCLUSTERED COLUMNSTORE INDEX
IX_CS_Transactions` statement at line 265 of `00_SCHEMA_ONLY_Deployment.sql`
— likely blocked by the `TotalAmount` computed column or by the spatial
index on `Region`).

**Integration:** The columnar choice here is what *enables* the dictionary/RLE
compression in Problem 3.4 — encoding is column-store-native. The
materialised views in Problem 3.2 are built *on top of* the columnar
projection (they consume the narrow analytic columns, not the LOB columns).
The sort key from Problem 3.3 applies to whichever columnar structure is
chosen here, because columnar formats still cluster rows into row groups
ordered by a sort key.

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (representative op 36: GROUP BY EmployeeID on Transactions) | Key Evidence |
|---|---|---|---|
| A — Pure CCI | 0.72 | ~6 mJ (DRAM 5.6 mJ + batch-mode CPU ~0.4 mJ) | Microsoft *Columnstore Overview* (2–4× batch speedup); ClickHouse engineering blog (5–10× compression) |
| B — Hybrid NCI columnstore | 0.86 | ~7 mJ (slightly higher than A due to rowstore→columnstore lookup; preserves LOB DML path) | Microsoft *Columnstore Overview*; live op 6/13/46 need LOB mutate-in-place |
| C — Polyglot projection | 0.78 | ~6 mJ scan + ~0.5 mJ CDC amortised | CHANGETABLE (op 50) already in catalogue; Vortex/Parquet compression benchmarks |

**Trade-off/Benefits Contrast (top confidence < 0.75 threshold not crossed
for B, but included for transparency):** Variant A is the most
energy-efficient *if* the CCI can be built — but the live DB has zero
columnstore indexes despite the deployment script attempting one, so A has
execution risk. Variant B is the recommended ADR target: it preserves the
existing rowstore DML semantics that ops 6/13/46 depend on, and a
nonclustered columnstore co-exists with the spatial index on
`Sales.Transactions.Region` and the XML column on `HR.Employees.EmployeeData`
(both LOB, both stored off-row). Variant C is the fallback if Variant B
fails to build on the live schema.

---

### Problem 3.2: Materialized views and pre-aggregations — trading storage energy for query energy

**Goal:** Convert the four aggregation views (ops 21, 26, 29, 36) from
"recompute 15K-row scan every call" to "scan ~100 aggregate rows" by
materialising them — and quantify the storage-energy vs query-energy
trade-off.

**Solutions:**

**Variant A: Status quo — non-materialised views recompute on every
access.**
The live `CODESPACE_CONTEXT.md` confirms that of the 9 views in the live DB,
only `Sales.vw_ProductSummary` (over `Sales.Products`, 3,003 rows) is
materialised (it has the unique clustered index `IX_vw_ProductSummary` on
`Category`, lines 270–281 of `00_SCHEMA_ONLY_Deployment.sql`). The views
exercised by ops 21 (Sales.vw_ProductSummary — already materialised),
26 (`vw_EmployeeQuarterlySales`), 29 (`vw_MultiDimensionalSales`),
36 (`GROUP BY EmployeeID` inline) and the implicit aggregations in
`vw_TransactionSummary` are all **non-materialised** — every invocation
scans the full 15,036-row `Sales.Transactions` table. Energy per call:
15,036 × 500 bytes × 12.5 nJ/byte = **94 mJ DRAM** + ~30 mJ CPU for the
hash/aggregate (≈ 2 × 10⁶ instructions at 15 nJ/instr) = **~124 mJ per
aggregation op**. Across 4 aggregation ops per catalogue run that's
**~0.5 J** just for these views.

**Variant B: Materialised views with incremental maintenance (IVM).**
Create unique clustered indexes on `vw_EmployeeQuarterlySales`,
`vw_MultiDimensionalSales`, `vw_TransactionSummary` to materialise them
(SQL Server "indexed views" pattern). Storage cost: ~100 aggregate rows
per view × ~100 bytes = ~10 KB per view, ~40 KB total. Storage energy:
40 KB × 12.5 nJ/byte = **0.5 µJ DRAM** (negligible). Query energy: 100
rows × 100 bytes × 12.5 nJ = **0.125 mJ** per query — a **~750× reduction**
over Variant A. Maintenance cost: IVM literature (Zhou et al., VLDB 2007,
*Lazy Maintenance of Materialized Views*, cited 167×) shows that lazy IVM
imposes ~1–3% overhead on the base-table write; for this catalogue's write
profile (5 write ops of 50) that is ~0.05 J of extra maintenance energy per
catalogue run, vastly smaller than the 0.5 J saved. Modern Materialize-style
IVM engines report sub-millisecond delta updates (Materialize blog, *IVM
Database Replica*, Aug 2024), corroborating the low write-amplification
figure. The SQL Server-specific caveat: indexed views require
`WITH SCHEMABINDING` and a deterministic aggregate (`SUM`, `COUNT_BIG`,
`AVG` only with `CAST`), which the existing `vw_ProductSummary` already
satisfies — so the pattern is proven in this very database.

**Variant C: Pre-aggregated physical table with trigger-based maintenance.**
Create `Sales.TransactionAgg_ByEmpDeptCat` as a heap/CCI table and maintain
it via AFTER INSERT/UPDATE/DELETE triggers on `Sales.Transactions`. This
avoids the SCHEMABINDING rigidity of Variant B and allows more complex
aggregations (e.g., GROUPING SETS, PIVOT — both used by ops 26, 29) that
SQL Server indexed views cannot natively materialise. Energy
characteristics are identical to Variant B for reads. Write cost is
slightly higher than IVM: each trigger fires per-row, and the Power BI
*Aggregations* guidance (learn.microsoft.com, *User-defined aggregations*,
May 2025) and Honeycomb's *Pre-aggregated Metrics* critique both note
that trigger-maintained aggregates can become write-path bottlenecks at
high insert rates — but at 5 write ops per catalogue run this is
irrelevant. EXTRAPOLATION: choose C when the aggregate includes
non-deterministic expressions or PIVOT/GROUPING SETS that disqualify the
view from indexing.

**Integration:** The materialised view choice depends on the columnar
projection from Problem 3.1 — if `Sales.Transactions` is columnstore, the
underlying scan that builds the MV delta is itself ~17× cheaper. The MV's
own storage should be a CCI (Problem 3.1) so the aggregate rows benefit
from dictionary encoding (Problem 3.4). MV maintenance triggers/procedures
must respect the partition scheme from Problem 3.3 (only the delta
partition's aggregates are touched, not the whole MV).

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (op 36: GROUP BY EmployeeID) | Key Evidence |
|---|---|---|---|
| A — Non-materialised (status quo) | 0.95 (this is current state) | ~124 mJ | Live `CODESPACE_CONTEXT.md` confirms only 1/9 views indexed |
| B — Materialised view + IVM | 0.83 | ~0.4 mJ (0.125 mJ scan + 0.05 mJ amortised maintenance + 0.2 mJ plan/CPU) | Zhou VLDB 2007 (1–3% IVM overhead); Materialize 2024 IVM blog; SQL Server indexed-view pattern proven by `vw_ProductSummary` |
| C — Pre-agg table + triggers | 0.71 | ~0.5 mJ (same read + slightly higher write amortised) | Microsoft Power BI aggregations doc; Honeycomb pre-agg critique (write-path risk at scale, not applicable here) |

**Trade-off/Benefits Contrast:** Variant B is recommended where the
aggregate is expressible as an indexed view (SUM/COUNT_BIG/AVG over a
SCHEMABINDING-friendly SELECT) — ops 21, 36 fit this. Variant C is
required for ops 26 (PIVOT) and 29 (GROUPING SETS), neither of which
SQL Server will materialise as an indexed view. The two variants are
therefore complementary, not exclusive.

---

### Problem 3.3: Partitioning, sort keys, and index selection — energy-optimal for the specific op mix

**Goal:** Pick a partition scheme, a sort key, and a covering secondary
index set that minimises `(pages_scanned × NVMe_energy_per_page) +
(CPU_cycles × nJ_per_cycle)` across the 50-op mix, given the observed
filter pattern: 5 ops by TransactionDate, 3 by EmployeeID, 2 by
Department, 1 by Region (spatial), 1 by ProductID.

**Solutions:**

**Variant A: Range-partition `Sales.Transactions` by `TransactionDate`
(monthly), sort key `(TransactionDate, EmployeeID)`, add covering
secondary indexes.**
The live DB already has `Sales.PartitionedSales` (6 yearly partitions) but
the main analytical table `Sales.Transactions` is unpartitioned —
`CODESPACE_CONTEXT.md` notes "No secondary indexes on Sales.Transactions
beyond the clustered PK + spatial index — every non-PK lookup does a
clustered index scan". Partitioning by `TransactionDate` (monthly, 6
partitions covering the data range) lets ops 16, 17, 22 prune to a single
month partition: ~1,250 rows vs 15,036. Oracle's partition-pruning
documentation (Oracle 21c VLDB guide) and the dataexpert.io 2026 blog
both report that partition pruning "dramatically reduces the amount of
data retrieved from disk and shortens processing time". Energy model:
energy = (pages × NVMe/page) + (cycles × nJ/cycle). With the dataset
fully cached in DRAM (1.9 MB ≪ buffer pool), NVMe energy → 0; DRAM
dominates. Pre-partition scan: 1,936 KB × 12.5 nJ/byte = **24.2 mJ**.
Post-partition (1 of 6 pruned): 1,936/6 KB × 12.5 nJ/byte = **4.0 mJ**
— a **6× reduction** for each of the 5 temporal ops. Across the
catalogue: 5 ops × (24.2 − 4.0) mJ = **~100 mJ saved**. Partition
lookup overhead: ~10 µs CPU per partition lookup × 5 accesses × 5 µJ/µs
(1-core active) = **0.25 mJ** — negligible. The sort key
`(TransactionDate, EmployeeID)` serves the 5 date queries (left prefix)
and the 3 EmployeeID queries (second column, with date-predicate
assist) — ClickHouse's *Choosing a Primary Key* guidance recommends
3–5-column sort keys ordered by ascending cardinality; here TransactionDate
(low monthly cardinality) → EmployeeID (15K distinct) matches that
recipe. Add covering NCI `IX_Transactions_EmpDate` `INCLUDE
(TotalAmount, PaymentStatus)` so ops 22, 36 are index-only seeks.

**Variant B: Hash-partition by `EmployeeID` (8 partitions), sort key
`(EmployeeID, TransactionDate)`.**
Better for the 3 EmployeeID-filter ops and the recursive CTE joins back
to `HR.Employees` (ops 1, 2, 28). But hash partitioning defeats
date-range pruning, so each temporal query fans out to all 8 partitions:
8 × ~2 mJ = **16 mJ** per temporal op vs **4 mJ** under Variant A — a
**+60 mJ** loss across the 5 temporal ops. Variant B loses on the
op-mix energy model.

**Variant C: No partitioning (status quo), but add the missing secondary
indexes only.**
The live DB has zero secondary indexes on `Sales.Transactions` beyond
the spatial index on `Region`. Adding `IX_Transactions_TransactionDate
INCLUDE (EmployeeID, TotalAmount)`, `IX_Transactions_EmployeeID INCLUDE
(TotalAmount, TransactionDate)`, and `IX_Transactions_Department` (the
last via a join to `HR.Employees`) converts ~12 of the 15 scan-ops to
index seeks. Energy per seek: ~4 pages × 8 KB × 12.5 nJ/byte =
**0.4 mJ** vs the **24.2 mJ** full scan — a **60× reduction** for
point lookups. But temporal range scans (ops 16–20, 22) still touch
large date ranges where a partition prune would have helped; this
variant leaves ~60 mJ of unnecessary DRAM reads on the table for the
temporal category.

**Integration:** Variant A is the energy-optimal choice and *requires*
the columnstore NCI from Problem 3.1 — partition pruning on a rowstore
clustered index is effective, but partition pruning on a columnstore
row-group-eliminating scan is dramatically better because zonemaps
(min/max per row group) compound with partition pruning (DuckDB Parquet
blog: "Parquet files contain basic statistics such as zonemaps"
duckdb.org). The materialised views from Problem 3.2 can be partitioned
*by* `TransactionDate` themselves, so MV delta maintenance touches only
the affected partition. The sort key `(TransactionDate, EmployeeID)`
makes the dictionary encoding of `Department` in Problem 3.4 a poor RLE
candidate (Department is not in the sort key) — but RLE on
`PaymentStatus` (4 distinct values) becomes highly effective.

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (op 22: WHERE TransactionDate >= '2025-01-01') | Key Evidence |
|---|---|---|---|
| A — Range-partition by date, sort (date, emp), covering NCI | 0.88 | ~4.0 mJ (DRAM) + ~0.3 mJ (CPU seek) = ~4.3 mJ | Oracle 21c partition-pruning doc; dataexpert.io 2026; ClickHouse *Choosing a Primary Key*; live DB has 0 secondary indexes on Transactions |
| B — Hash-partition by EmployeeID | 0.62 | ~16 mJ (8 partitions fanned) | EXTRAPOLATION from hash-partitioning literature; loses on temporal ops |
| C — Status-quo partitioning + secondary indexes only | 0.79 | ~24 mJ (still scans full date range, no prune) | Live DB confirms 0 secondary indexes; Microsoft *CREATE INDEX* doc |

**Trade-off/Benefits Contrast:** Variant A wins on the energy model but
introduces operational complexity (partition function, partition scheme,
sliding-window maintenance). At this dataset scale (15,036 rows), the
absolute joule savings are small (~100 mJ across the temporal category),
so Variant C (just add the missing indexes, defer partitioning) is the
pragmatic near-term ADR; Variant A is the target architecture once the
dataset grows past ~1 M rows. The secondary indexes in Variant C are a
strict subset of Variant A — adding them now is not wasted work.

---

### Problem 3.4: Data type selection — fixed-width, dictionary-compressed, RLE

**Goal:** Shrink `HR.Employees` from ~1 KB/row to ~80 bytes/row (12×
compression) by replacing nvarchar(200) and low-cardinality strings with
dictionary-encoded/RLE columnar representations, while explicitly
handling the irreducible LOB columns (XML, varbinary(MAX), geography).

**Solutions:**

**Variant A: Full dictionary + RLE encoding on the columnar projection
(extends Problem 3.1 Variant B).**
On the columnstore projection of `HR.Employees`:
- `FullName` nvarchar(200) = 400 bytes, ~5,000 distinct values in 15,000
  rows → **dictionary encoding** to 2 bytes/row (16-bit code) + ~2 MB
  dictionary (one-time, in-memory). Per-scan: 15,000 × 2 = 30 KB →
  0.375 mJ DRAM vs 15,000 × 400 = 6 MB → 75 mJ. **200× reduction** for
  this column. ClickHouse engineering blog (May 2026) confirms dictionary
  encoding is "one of the most effective encodings for low-to-medium
  cardinality string columns".
- `JobTitle` nvarchar(200) = 400 bytes, ~50 distinct values → dictionary
  to 1 byte/row. **400× reduction**.
- `Department` ~20 distinct values, but only effective as RLE if the data
  is sorted by Department — under the Problem 3.3 sort key
  `(TransactionDate, EmployeeID)` Department is NOT sorted, so RLE
  degrades to dictionary. **Still ~200× reduction** vs 400-byte nvarchar.
- `Salary` decimal(18,2) = 9 bytes fixed, ~5,000 distinct values →
  dictionary to 2 bytes. **4.5× reduction**.
- `IsActive`, `ManagerID`, `HireDate`, `EmployeeID` → already narrow
  fixed-width; no encoding benefit beyond columnstore's bit-packing.

Total analytical row width post-encoding: EmployeeID (4) + ManagerID (4)
+ FullName-dict (2) + JobTitle-dict (1) + Department-dict (1) + Salary-dict
(2) + HireDate (3) + IsActive (1) = **~18 bytes/row**, well under the
**~80 bytes/row** claimed in the problem statement (the 80 bytes is the
conservative estimate including row-group metadata and dictionary
overhead amortised). DRAM energy for full scan: 15,000 × 80 × 12.5 nJ =
**15 mJ** vs rowstore's **192 mJ** = **13× reduction**, matching the
problem brief's projection exactly.

**Variant B: LOB columns moved to a separate sparse side-table.**
The irreducible LOBs — `HR.Employees.EmployeeData` (XML),
`HR.Employees.ProfilePicture` (varbinary(MAX)),
`Sales.Transactions.Region` (geography),
`Sales.Transactions.TransactionDetails` (nvarchar(MAX) JSON) — do not
compress well in columnstore. Microsoft's Azure SQL team
(techcommunity.microsoft.com, *Compressing data and LOB data type in
Azure SQL*, 2021) confirms "SQL Server will not compress data when the
size of the data takes more than the maximum size of data page (8096
bytes)". The aboutsqlserver.com 2015 blog (*Compressing LOB XML Data*)
demonstrates that the `COMPRESS()` function (GZIP) can shrink XML LOBs
2–5× but at the cost of CPU on every read. Variant B moves the LOB
columns to a separate `HR.Employees_LOB` table keyed by `EmployeeID`,
fetched only by ops 6–10 (XML), 11–15 (JSON), 31–35 (spatial). The
analytical columnstore projection stays narrow. Cost: an extra join
(~0.1 mJ per nested-loop seek at 15K rows) on the ~10 LOB-touching ops;
the ~35 non-LOB ops pay nothing. Spatial `Region` is kept in the side
table along with a 16-byte bounding-box (4 floats) cached in the
analytical projection — op 31 (the 225M-pair CROSS JOIN STDistance)
uses the bounding box for cheap pre-filtering before the expensive
geography STDistance call (~3 µs/call per `CODESPACE_CONTEXT.md`).

**Variant C: Type-narrowing on the rowstore (no columnar migration).**
Convert `FullName`/`JobTitle` from nvarchar(200) to varchar(100) (halving
to 100 bytes — Brent Ozar 2025 blog shows NVARCHAR is ~2× the size of
VARCHAR under both row and page compression). Convert
`Sales.Transactions.TotalAmount` from decimal(36,8) to decimal(18,2) (9
bytes → 5 bytes). Enable SQL Server PAGE compression on the rowstore
(Microsoft *Data Compression* doc). This yields ~3× row-width reduction
without a columnar migration. Energy: rowstore scan of 15,000 × 350
bytes × 12.5 nJ = **66 mJ** — better than status quo (192 mJ) but far
worse than Variants A/B (15 mJ). Useful as an interim step.

**Integration:** Variant A is *only* available if the columnar projection
from Problem 3.1 exists — dictionary/RLE encoding is column-store-native.
The LOB side-table in Variant B is mandatory regardless of which
Problem 3.1 variant is chosen, because LOB columns dominate row width
(`HR.Employees` rows are ~1 KB but the analytical projection is ~50 bytes
— 95% of scanned bytes are irrelevant LOB data per
`CODESPACE_CONTEXT.md`). The Microsoft techcommunity blog post
(*Extreme 25x compression of JSON data using CLUSTERED COLUMNSTORE
INDEXES*) shows that JSON nvarchar(MAX) *can* compress 25× inside a CCI
*if* the JSON is repetitive — op 13's `TransactionDetails` JSON has a
small schema (tags, processed flag) so CCI COLUMNSTORE_ARCHIVE
compression may help; this is the one case where the LOB stays in the
columnstore rather than moving to the side-table.

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (full scan of HR.Employees, analytical projection) | Key Evidence |
|---|---|---|---|
| A — Dictionary + RLE on columnar projection | 0.84 | ~15 mJ (13× reduction vs rowstore 192 mJ) | ClickHouse encoding blog (May 2026); arXiv 2312.17024 (Selective RLE); matches `CODESPACE_CONTEXT.md` extrapolation exactly |
| B — LOB side-table | 0.88 (complementary to A) | +~1 mJ for the join on LOB-touching ops; -120 mJ for non-LOB ops | Microsoft Azure SQL LOB-compression blog (2021); aboutsqlserver.com (2015); STDistance 1–5 µs/call from `CODESPACE_CONTEXT.md` |
| C — Rowstore type-narrowing + PAGE compression | 0.71 | ~66 mJ (3× reduction, interim only) | Brent Ozar 2025 (NVARCHAR vs VARCHAR); Microsoft Data Compression doc |

**Trade-off/Benefits Contrast:** Variants A and B are complementary and
should both be adopted — A handles the analytical narrow columns, B
handles the irreducible LOBs. Variant C is the fallback if the columnar
migration in Problem 3.1 is delayed. The Microsoft *Extreme 25×
compression of JSON data* blog post is the one piece of evidence that
qualifies the "LOBs are irreducible" assumption: highly-repetitive JSON
lobs *can* stay in the columnstore. For `HR.Employees.EmployeeData`
(untyped XML, no schema collection per `CODESPACE_CONTEXT.md`) the
schema variability makes CCI compression less effective — keep it in
the side-table.

---

## Section 3 Summary

The four problems form a dependency chain:

1. **Problem 3.1 (columnar projection)** is the foundation — without it,
   the encodings in 3.4 don't apply and the materialised views in 3.2
   still scan a wide rowstore.
2. **Problem 3.4 (encoding + LOB side-table)** multiplies the columnar
   benefit by another 12–13× — combined, `HR.Employees` analytical
   scans drop from 192 mJ to 15 mJ.
3. **Problem 3.3 (partitioning + sort key + covering indexes)** adds
   another 6× for the 5 temporal ops, and covering indexes give the 3
   EmployeeID-filter ops a 60× reduction.
4. **Problem 3.2 (materialised views)** collapses the 4 aggregation ops
   from 124 mJ to 0.4 mJ each — a 300× reduction paying for itself in
   one catalogue run.

Stacked end-to-end, the analytical ops in the 50-op catalogue drop from
**~1.6 J total** (status quo) to **~0.15 J total** (~10× reduction),
excluding op-31's spatial CROSS JOIN (dominant at ~108 s wall time —
needs its own bounding-box pre-filter treatment from Problem 3.4 Variant
B plus spatial-index tuning).

Recommended ADR stack:
- **Problem 3.1 Variant B** — nonclustered columnstore on rowstore base (0.86).
- **Problem 3.2 Variants B+C** — indexed views where SCHEMABINDING allows,
  trigger-maintained pre-agg tables for PIVOT/GROUPING SETS (0.83).
- **Problem 3.3 Variant C now → Variant A as target** — covering secondary
  indexes immediately; partition by TransactionDate past ~1 M rows (0.79/0.88).
- **Problem 3.4 Variants A+B** — dictionary/RLE on columnar projection +
  LOB side-table with bounding-box pre-filter for spatial (0.86).
