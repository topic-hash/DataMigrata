# Section 2 — Most Energy-Efficient Database Operations

> Problem Catalogue entry for the DataMigrata energy-migration research project.
> All joule figures are either (a) drawn from a named published benchmark, or
> (b) explicitly labelled **EXTRAPOLATION** using the resource-to-joule
> constants in `CODESPACE_CONTEXT.md` (CPU ~10 W active per core; DRAM
> ~12.5 nJ/byte; NVMe ~0.75 mJ per 4 KB page; `geography::STDistance`
> ~1–5 µs/call). Live schema, row counts, and index gaps are taken from the
> same file — `HR.Employees` 15 000 rows / 3 088 KB; `Sales.Transactions`
> 15 036 rows / 1 992 KB; **zero** secondary indexes on either table beyond
> PK + spatial; **zero** columnstore indexes anywhere.

The four problems below cover the dominant operator-level decisions for the
50-operation workload: access-path selection (2.1), join algorithm (2.2),
aggregation strategy (2.3), and physical storage / execution model (2.4).
Operation 31 — the 15 K × 15 K spatial `CROSS JOIN` taking ~108 s wall time —
is treated explicitly in 2.2 because 108 s × 10 W ≈ **1 080 J** per
invocation, exceeding the combined joule budget of the other 49 operations
by an estimated two orders of magnitude.

---

### Problem 2.1: Scan vs index seek vs index-only scan — energy profiles for the live schema

**Goal:** For the analytical operations that today scan a clustered index
(`Sales.Transactions` PK or `HR.Employees` PK), pick the access path that
minimises joules per execution, given that the live schema ships **no
secondary indexes** on either table (only `Email` on `HR.Employees`, only the
spatial index on `Sales.Transactions`). Representative operations: op 36
(`GROUP BY EmployeeID` over `Sales.Transactions`, 15 K rows), op 1 (recursive
CTE self-join on `HR.Employees.ManagerID`, ~7 levels), op 26/29/30 (aggregations
on `Sales.Transactions`).

**Solutions:**

**Variant A: Status quo — clustered index scan.**
Today every non-PK lookup on `Sales.Transactions` and `HR.Employees` resolves
to a clustered index scan (codespace inventory confirms `Index KB = 0` on both
tables). For op 36 the scan reads 15 036 rows × ~500 bytes ≈ 7.5 MB; for op 1
each recursion level re-scans 15 000 × ~1 024-byte rows (~15 MB) because
`ManagerID` is not indexed. **EXTRAPOLATION:** DRAM transfer for op 36 is
7.5 MB × 12.5 nJ/byte ≈ **0.094 J**; for op 1, 15 MB × 12.5 nJ/byte × ~7
levels ≈ **1.3 J** of DRAM traffic. CPU is the larger component: op 1 ≈
0.5–1 s CPU ≈ **5–10 J**, op 36 ≈ 50 ms CPU ≈ **0.5 J**. NVMe energy is
negligible because the buffer pool holds the full 8 MB user dataset — matching
the codespace note that *“at this scale, I/O energy is negligible; CPU energy
dominates”*.

**Variant B: Add a nonclustered index on the predicate/group column.**
`CREATE NONCLUSTERED INDEX ix_Tx_EmployeeID ON Sales.Transactions(EmployeeID)`
for op 36; `CREATE NONCLUSTERED INDEX ix_Emp_ManagerID ON
HR.Employees(ManagerID)` for op 1. The nonclustered B-tree leaf entry is
~16–24 bytes vs the ~1 024-byte base row, so a full index scan reads ~360 KB
instead of ~15 MB. **EXTRAPOLATION:** op 1 per-level DRAM drops from 0.19 J to
~4.5 mJ (~40× reduction); the recursive Index Seek pattern cuts CPU from
~500 ms to ~30 ms per level — total op 1 energy falls to ~**0.3–0.5 J**.
The `dba.stackexchange.com/q/53348` thread reports exactly this improvement
after adding a `ManagerID` index on a recursive CTE.

**Variant C: Covering index with INCLUDE (index-only scan).**
`CREATE NONCLUSTERED INDEX ix_Tx_EmpID_cover ON Sales.Transactions(EmployeeID)
INCLUDE (TotalAmount, Quantity, UnitPrice)`. INCLUDE columns live on the leaf
page so the optimizer produces an *index-only scan* with no Key Lookup
(Microsoft Docs `use-the-index-luke.com/.../operations`; Red Gate “Using
Covering Indexes”). **EXTRAPOLATION:** the covering-index leaf is ~60
bytes/row × 15 000 = 900 KB and is sorted on `EmployeeID`, so the optimizer
switches from a Hash Aggregate to a Stream Aggregate (no hash table, no DRAM
for buckets). Op 36 energy drops to ~10 ms CPU ≈ **0.1 J** — ~5× better than
Variant B and ~50× better than Variant A. Trade-off (per `sqland.wordpress.com`
2024): every `INSERT` updates one extra B-tree, adding ~1–3 ms CPU per insert
(≈ 10–30 µJ at 10 W).

**Integration:** Variant C for `Sales.Transactions(EmployeeID)` is the
prerequisite for the Stream Aggregate strategy in 2.3 and the merge join in
2.2 (sorted input is required). The `ManagerID` index from Variant B is a
prerequisite for replacing the recursive CTE in op 1 with a single-pass
`hierarchyid` traversal on `HR.OrgChart` (already clustered on `hierarchyid`).

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (representative op) | Key Evidence |
|---|---|---|---|
| A — clustered scan (status quo) | 0.95 | ~5–10 J (op 1), ~0.5 J (op 36) | Codespace context: “60 % of the 50 ops do clustered index scans”; Tsiatsis et al. SIGMOD 2010 “Analyzing the Energy Efficiency of a Database Server” (`adrem.uantwerpen.be/sites/default/files/energy_sigmod10.pdf`) — CPU dominates scan energy |
| B — nonclustered index | 0.85 | ~0.3–0.5 J (op 1), ~0.2 J (op 36) | `dba.stackexchange.com/q/53348` (ManagerID index on recursive CTE); Red Gate “Using Covering Indexes”; EXTRAPOLATION via codespace DRAM/CPU constants |
| C — covering index with INCLUDE | 0.80 | ~0.1 J (op 36) | Microsoft Docs SQL Server execution-plan operations (`use-the-index-luke.com`); `sqland.wordpress.com` covering-vs-non-covering deep-dive; EXTRAPOLATION |

Top confidence ≥ 0.75 → no Trade-off/Benefits Contrast subsection required.

---

### Problem 2.2: Join algorithm energy — hash vs merge vs nested-loop under the live cardinalities

**Goal:** For the three join-shaped operations in the live workload — op 31
(`CROSS JOIN` of `Sales.Transactions` with itself, 15 K × 15 K = 225 M pairs,
~108 s wall), op 40 (batch-mode join of `Sales.Transactions` 15 K to
`HR.Employees` 15 K), op 5 (transitive closure via recursive self-joins on
`HR.Employees`) — pick the physical join operator that minimises joules.
Nested-loop is O(n·m) CPU; hash is O(n+m) CPU plus DRAM for the hash table;
merge is O(n+m) CPU but requires both inputs pre-sorted.

**Solutions:**

**Variant A: Nested-loop join (current behaviour for op 31).**
Op 31 is the workload’s single largest energy consumer — the codespace context
labels it *“the energy outlier: 225 M geography distance calculations, ~108 s
wall time”*. Using the codespace CPU constant: 108 s × 10 W ≈ **~1 080 J** of
CPU-package energy. Tsiatsis et al. SIGMOD 2010 measured that CPU-intensive
operators like `STDistance` math drive package power to its TDP ceiling
disproportionately to utilisation, so this is conservative. The codespace
`STDistance` constant (1–5 µs/call) × 225 M calls = 225–1 125 s of pure spatial
math, consistent with the observed 108 s on multi-core execution. Microsoft
Docs (`learn.microsoft.com/.../stdistance-geography-data-type`) explicitly
notes that `STDistance` only uses the spatial index when invoked inside a
`WHERE Filter(@cell, …)` predicate — a bare `CROSS JOIN` does not qualify,
which is why op 31 ignores the existing `SIDX_Transactions_Region` spatial
index. The nested-loop choice is *pareto-dominated*: slowest *and* most
energy-expensive.

**Variant B: Hash join (optimal for op 40 and the build side of op 5).**
For op 40 (`Sales.Transactions` 15 K ⨝ `HR.Employees` 15 K on `EmployeeID`),
hash join is O(n+m). The build-side hash table for 15 K employees (key +
projected columns) is ~1.5 MB of DRAM; the probe is a single streamed scan.
**EXTRAPOLATION:** DRAM for the hash table is 1.5 MB × 12.5 nJ/byte ≈
**0.019 J** (write + read ≈ 0.05 J total); CPU is ~10–20 ms ≈ 0.1–0.2 J.
Total ≈ **0.25 J** — three orders of magnitude better than a nested-loop
fall-back (225 M comparisons × ~10 ns ≈ 2.25 s CPU ≈ 22.5 J). Seattle Data
Guy’s “Back To The Basics With SQL: Hash, Merge” and Oracle forum consensus
confirm two equal-size large inputs call for a hash join. Tsiatsis et al.
measured that the hash-join *build* phase drives CPU into its highest power
state, so there is a fixed ~5 W overhead above baseline during build — at
n=m=15 K the break-even is comfortably below the workload size.

**Variant C: Merge join with sorted inputs (op 31 rewrite and op 5).**
Merge join is O(n+m) CPU with no hash-table DRAM cost, but *requires both
inputs sorted*. For op 5, rewrite the recursive CTE using the existing
`HR.OrgChart.hierarchyid` clustered index — the closure becomes a single
range scan, an ordered “merge-style” traversal with no per-level re-scan.
**EXTRAPOLATION:** CPU drops from ~7 levels × 30 ms to a single ~15 ms scan
≈ **0.15 J**. For op 31, the right rewrite is not strictly a merge join but a
*spatial index join with bounding-box prefilter*: rewrite `CROSS JOIN …
STDistance` as `WHERE a.Region.STDistance(b.Region) < @d` with an explicit
`WITH (SPATIAL_INDEX)` hint. AboutSQLServer’s 2013 bounding-box article and
the Microsoft spatial-index rules establish that this rewrites 225 M distance
calls down to ~1–5 % (bounding-box pruning) — ~2–11 M calls × 2 µs ≈ 4–22 s
CPU ≈ **40–220 J**, a **5–25× reduction** from Variant A. Prefiltered,
ordered input is the most energy-efficient join shape on modern CPUs because
the spatial index does work that the CPU would otherwise do at ~10 W.

**Integration:** Variant C for op 5 depends on Variant B from 2.1 (the
`ManagerID` index) plus the existing `HR.OrgChart.hierarchyid` clustered
index. Variant C for op 31 needs no new structure — only a SQL rewrite that
uses the existing `SIDX_Transactions_Region` spatial index. The hash-join
choice for op 40 is the optimizer default; it becomes energy-optimal only
*because* 2.1 ensures a seekable access path on the build side.

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (representative op) | Key Evidence |
|---|---|---|---|
| A — nested loop (current op 31) | 0.97 | ~1 080 J (op 31), ~22.5 J (op 40 if forced) | Codespace: 108 s wall; STDistance 1–5 µs/call; Tsiatsis et al. SIGMOD 2010; Microsoft Docs STDistance spatial-index rules |
| B — hash join | 0.88 | ~0.25 J (op 40) | Seattle Data Guy “Hash, Merge, Nested Loop”; Oracle forums; EXTRAPOLATION |
| C — merge join / spatial index prefilter | 0.82 | ~0.15 J (op 5 via hierarchyid), ~40–220 J (op 31 rewrite) | AboutSQLServer 2013 bounding-box article; Microsoft Docs spatial-index usage; Data Education 2015 “Re-Inventing the Recursive CTE”; EXTRAPOLATION |

Top confidence ≥ 0.75 → no Trade-off/Benefits Contrast subsection required.
Note: Variant C for op 31 is the single largest absolute joule saving in the
whole catalogue (~860–1 040 J per execution saved).

---

### Problem 2.3: Aggregation energy — hash-based vs sort-based vs pre-computed (materialized view)

**Goal:** For the four aggregation operations on `Sales.Transactions` —
op 21 (materialised view, currently **not** indexed), op 26 (`PIVOT`),
op 29 (`GROUPING SETS`, multi-dimensional), op 30 (window functions) and
op 36 (`GROUP BY EmployeeID`) — pick the aggregation strategy that minimises
joules per execution. The live DB has a SCHEMABINDING view `vw_ProductSummary`
but it has no clustered index, so it recomputes on every access (codespace
index inventory shows zero indexed views).

**Solutions:**

**Variant A: Hash aggregate (default optimizer choice today).**
SQL Server picks a Hash Match (Aggregate) when the input is unsorted and the
group cardinality fits in memory. For op 36 (15 036 rows grouped by
`EmployeeID`, ~15 K groups), the hash table is ~50 bytes/group × 15 K =
750 KB. **EXTRAPOLATION:** DRAM is 750 KB × 12.5 nJ/byte ≈ **0.009 J** (write
+ read ≈ 0.02 J total); CPU for hashing 15 K rows is ~20–40 ms ≈ 0.2–0.4 J.
Total ≈ **0.3 J**. For op 29 (GROUPING SETS, multi-dimensional), the hash
table is 3–5× denser — ~1.5 J. The energy risk, documented by Erik Darling
(`erikdarling.com/.../hash-aggregate-spills`), is spill to `tempdb`: each 4 KB
spill page costs ~0.75 mJ × pages spilled. At 15 K rows this is unlikely for
op 36 but plausible for op 29.

**Variant B: Sort + Stream Aggregate.**
The Stream Aggregate requires sorted input. With the covering index from 2.1
Variant C the input is already sorted on `EmployeeID`, so the aggregate is a
single streaming pass with no hash table.
`blog.sqlauthority.com/2020/02/17/sql-server-stream-aggregate-and-hash-aggregate`
documents the sorted-input requirement. **EXTRAPOLATION:** the Stream
Aggregate costs ~5–10 ms CPU ≈ **0.05–0.1 J** — a 3–5× improvement over
Variant A. If the input is *not* pre-sorted, the Sort operator adds
O(n log n) comparisons; the arXiv 2024 “Hash-Based vs. Sort-Based Group”
paper measured that sort-based aggregation retains full records in memory,
so it uses 5–10× more DRAM at high group counts. For op 36 at 15 K rows this
is ~75 KB extra working set (negligible), but for op 29 the sort working set
can exceed the memory grant and spill. The spill-to-NVMe cost is the energy
cliff: each 4 KB page written + re-read is ~1.5 mJ; a 50 MB spill ≈ 12 800
pages × 1.5 mJ ≈ **19 J** — an order of magnitude worse than Variant A.

**Variant C: Pre-computed materialized view (indexed view).**
The live DB has `vw_ProductSummary` with SCHEMABINDING but no clustered index —
so it is a *virtual* view that recomputes on every access. `CREATE UNIQUE
CLUSTERED INDEX cix_vw_ProductSummary ON vw_ProductSummary(ProductID)`
materialises it. Microsoft Docs
(`learn.microsoft.com/.../develop-materialized-view-performance-tuning`)
states materialised views “provide a low maintenance method for complex
analytical queries to get fast performance without any query change”. The
`materialize.com/blog/views-indexes` benchmark shows 10–100× speedups for
aggregations hitting a materialised view. **EXTRAPOLATION:** op 21, 26, 29, 30
against the materialised view become a clustered index scan on a
pre-aggregated row set (~300 rows for ProductID-level aggregates) — CPU ~1–5
ms ≈ **0.01–0.05 J**. The trade-off (`sqlsolutionsgroup.com/indexed-view`,
`erikdarling.com/.../indexed-view-maintenance`) is maintenance energy: every
`INSERT`/`UPDATE`/`DELETE` on `Sales.Transactions` must synchronously update
the indexed view, adding ~5–20 ms CPU per write (≈ 0.05–0.2 J per write). At
the codespace’s read-analytical write rate, this is a clear net win.

**Integration:** Variant C is the prerequisite for the pre-aggregation
strategy in Section 3. Variant B (Stream Aggregate) is only achievable if 2.1
Variant C (the covering index) is in place; otherwise it collapses back to
Sort + Hash Aggregate — the worst case. Variant A is the safe default for
ad-hoc aggregations that do not justify a materialised view.

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (representative op) | Key Evidence |
|---|---|---|---|
| A — hash aggregate | 0.90 | ~0.3 J (op 36), ~1.5 J (op 29) | `blog.sqlauthority.com/2020/02/17` stream vs hash; Erik Darling hash-spill write-up; EXTRAPOLATION |
| B — sort + stream aggregate | 0.78 | ~0.05–0.1 J (with covering index), ~19 J (if spills) | arXiv 2024 “Hash-Based vs. Sort-Based Group” (`arxiv.org/html/2411.13245v2`); `blog.sqlauthority.com` stream-aggregate; EXTRAPOLATION |
| C — materialised (indexed) view | 0.85 | ~0.01–0.05 J per query; ~0.05–0.2 J maintenance per write | Microsoft Docs materialised-view tuning; `materialize.com/blog/views-indexes`; `sqlsolutionsgroup.com/indexed-view`; EXTRAPOLATION |

Top confidence ≥ 0.75 → no Trade-off/Benefits Contrast subsection required.
Acknowledged conflict: Variant B is *faster* than Variant A only when the
covering index exists; otherwise it is *slower and more energy-expensive*
because of the sort. Variant C minimises query-time joules but shifts energy
to write-time — the right choice depends on read:write ratio, which the
codespace context indicates is read-heavy.

---

### Problem 2.4: Compression, vectorization, and SIMD — quantified joule savings

**Goal:** The live DB has **zero columnstore indexes** and **no row/page
compression** on any rowstore table. `HR.Employees` rows are ~1 KB wide
because of `EmployeeData xml(-1)`, `ProfilePicture varbinary(-1)`, and
`nvarchar(200)` columns, yet analytical queries on ops 1, 5, 36, 40 only
need ~50 bytes per row (`EmployeeID`, `ManagerID`, `Department`, `Salary`).
Quantify the joule savings if the analytical workload moved to (a) a
columnstore index with dictionary encoding, (b) a vectorised execution
engine, (c) SIMD-accelerated scan/aggregate.

**Solutions:**

**Variant A: Rowstore, no compression (current).**
Today the optimizer reads the full 1 KB row to access the 50-byte analytical
subset. For op 1, each recursion level reads 15 000 × 1 024 bytes = 15 MB;
over ~7 levels that is ~105 MB of DRAM traffic. **EXTRAPOLATION:**
105 MB × 12.5 nJ/byte ≈ **1.3 J** of DRAM transfer, plus ~0.5–1 s CPU ≈
5–10 J — matching the Variant A estimate in 2.1. The codespace observation
that *“LOB columns dominate row width … 95 % of scanned bytes are irrelevant
LOB data”* is the direct motivation for Variants B and C. Tsiatsis et al.
SIGMOD 2010 measured that rowstore scans drive CPU into a high-power state
disproportionate to useful work because the CPU is stalled on memory
subsystem traffic — i.e. the 95 % of irrelevant bytes cost real joules, not
just latency.

**Variant B: Columnstore index with dictionary encoding.**
A nonclustered columnstore index on `HR.Employees(EmployeeID, ManagerID,
Department, Salary, HireDate)` stores each column separately and applies
dictionary encoding to low-cardinality string columns (`Department` —
typically <100 distinct values → ~1-byte code instead of ~40-byte nvarchar).
The SQLShack “Columnstore Index Enhancements” benchmark reports 92 %
compression vs rowstore; Microsoft Docs states columnstore “improves query
performance typically by two to four times”. Abadi et al. “Design and
Implementation of Modern Column-Stores” (UMD, cited 487×) is the canonical
reference for why columnar cuts both I/O and CPU. **EXTRAPOLATION:** for op 1,
the columnstore scan reads ~50 bytes/row × 15 000 = 750 KB per level (vs 15 MB
rowstore). After dictionary encoding the effective DRAM traffic is ~150–250 KB
per level. Over 7 levels: ~1.5 MB × 12.5 nJ/byte ≈ **0.02 J** — a ~65×
reduction in DRAM energy alone. CPU drops proportionally because the CPU is no
longer memory-stalled; total op 1 energy falls from ~5–10 J to ~0.2–0.5 J. The
CMU 15-721 paper (`15721.courses.cs.cmu.edu/.../abadi-sigmod2006.pdf`)
documents that dictionary-encoded columns also enable *operator-level
short-circuiting* (`WHERE Department = 'Sales'` becomes integer equality on the
dictionary code), further cutting retired CPU instructions and CPU-package
energy.

**Variant C: Vectorised / SIMD execution (DuckDB / MonetDB / MSSQL batch mode).**
On top of the columnar layout, a vectorised engine processes data in batches
of 1 024–4 096 values per operator call and uses SIMD (AVX2 / AVX-512) to
apply the same operation to 4–16 values per CPU instruction. The MonetDB/X100
paper (Boncz et al.) reports “up to 100× faster than traditional engines”; the
more conservative Microsoft Learn figure for SQL Server batch mode is 2–4×.
InfoQ’s “Columnar Databases and Vectorization” and Cockroach Labs’
“How we built a vectorized execution engine” both explain the mechanism:
vectorisation keeps the CPU pipeline saturated and exploits data-level
parallelism, so joules/instruction drops because the instruction count drops.
**EXTRAPOLATION:** for op 36 on a columnstore, batch-mode aggregation retires
~15 K / 1 024 ≈ 15 batches × ~50 SIMD instructions ≈ 750 instructions for the
aggregate, vs ~150 K scalar instructions in row mode. At ~10 W active CPU
(~10 nJ/instruction at 1 GHz retired rate), CPU-package energy drops from
~0.5 J (Variant B without SIMD) to ~0.05 J. Combined with Variant B DRAM
savings, op 36 total drops from ~0.5 J (current rowstore) to ~0.05 J — a
**10× reduction**. For op 1 the recursive self-join on columnstore + batch
mode would drop from ~5–10 J to ~0.1–0.3 J. The 2025 ACM paper “Selective
Late Materialization in Modern Analytical”
(`dl.acm.org/doi/10.14778/3749646.3749717`) notes that late-materialisation
*latency* benefits diminish once a vectorised engine is in place, but the
*energy* benefit persists because it cuts DRAM traffic, which is the dominant
energy cost on a vectorised engine.

**Integration:** Variant B is the foundation for Variant C (SIMD requires a
columnar layout to operate on contiguous values). Variant B for
`HR.Employees` is also the prerequisite for the Variant C merge-join rewrite
of op 5 in 2.2 (columnstore enables merge-join-friendly ordered scans). The
materialised view from 2.3 Variant C could itself be implemented as a
columnstore-indexed view, compounding the savings. The UPP paper (ACM 2025,
`dl.acm.org/doi/10.1145/3695053.3731005`) reports predicate pushdown on
columnar storage reduces system-wide energy by 9–87 % versus Spark’s regular
execution — a range that brackets the extrapolated savings above.

**ADR:**

| Variant | Confidence (0.0–1.0) | Joule Estimate (representative op) | Key Evidence |
|---|---|---|---|
| A — rowstore, no compression (current) | 0.95 | ~5–10 J (op 1), ~0.5 J (op 36) | Codespace: ~1 KB/row, 95 % irrelevant bytes; Tsiatsis et al. SIGMOD 2010 memory-stall energy; EXTRAPOLATION |
| B — columnstore + dictionary encoding | 0.85 | ~0.2–0.5 J (op 1), ~0.05 J (op 36, DRAM only) | SQLShack 2018 “Columnstore Index Enhancements” (−92 %); Microsoft Docs columnstore overview (2–4×); Abadi et al. UMD column-stores paper (cited 487×); EXTRAPOLATION |
| C — vectorised + SIMD (batch mode) | 0.80 | ~0.1–0.3 J (op 1), ~0.05 J (op 36, total) | MonetDB/X100 (Boncz); DuckDB discussion (`medium.com/@duckweave`); InfoQ 2018 vectorization; Cockroach Labs vectorised engine; Microsoft Learn batch-mode (2–4×); ACM 2025 Selective Late Materialization; EXTRAPOLATION |

Top confidence ≥ 0.75 → no Trade-off/Benefits Contrast subsection required.
Acknowledged conflict: “most performant” and “least energy” diverge at the
margin — a hash table (Problem 2.2 Variant B) uses DRAM energy but saves CPU
energy; a columnstore (Variant B here) is slower for single-row OLTP point
lookups but dramatically lower energy for the analytical scans that dominate
this workload. The codespace context establishes that the workload is
read-analytical, so the columnstore trade-off favours energy efficiency
without sacrificing latency on the operations that matter.

---

## Section 2 summary

The four problems form a dependency chain: the access-path choices in 2.1
enable the join-algorithm choices in 2.2; the covering index from 2.1 is the
prerequisite for the Stream Aggregate in 2.3; the materialised view from 2.3
is the prerequisite for pre-aggregation in Section 3; the columnstore layout
from 2.4 is the prerequisite for SIMD execution and the merge-join rewrites
in 2.2.

The single largest absolute joule saving available in the live schema is the
**op 31 spatial CROSS JOIN rewrite** (2.2 Variant C): from ~1 080 J to
~40–220 J per execution — a saving of 860–1 040 J per run, achieved with
zero schema change (the spatial index already exists) and a one-line SQL
rewrite. The second largest is the **op 1 recursive CTE rewrite** using
`HR.OrgChart.hierarchyid` (2.1 Variant B + 2.2 Variant C): from ~5–10 J to
~0.15 J, a ~30–70× reduction.

The cumulative effect of adopting Variants B/C across all four problems is
estimated (EXTRAPOLATION) at a **20–50× reduction in per-query joules** for
the analytical subset of the 50 operations, with the dominant contribution
coming from the columnstore transition (2.4) and the spatial-join rewrite
(2.2).
