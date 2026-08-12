# minikeyvalue — Knowledge Base Entry

> **Added:** 2026-07-28
> **Positioning:** Supplementary storage-layer candidate (NOT a SQL engine candidate)
> **Relevance to energy-migration project:** Indirect — potential blob-storage layer for LOB columns during migration and as a physical-structure alternative

---

## What it is

**minikeyvalue** is a distributed key-value store written in ~1000 lines of Go by George Hotz (geohot), used in production at [comma.ai](https://comma.ai) for petabyte-scale self-driving car data storage.

- **Repository:** https://github.com/geohot/minikeyvalue (verified HTTP 200, ~3,150 stars, MIT license)
- **Language:** Go (master server) + nginx (volume server) + LevelDB (indexing)
- **API:** HTTP — `GET /key` (302 redirect to nginx), `PUT /key`, `DELETE /key`
- **Value size:** Optimized for 1 MB – 1 GB blobs
- **Scale:** Designed for billions of files / petabytes of data
- **Production use:** comma.ai blog (https://blog.comma.ai/scaling-for-10x-user-growth) confirms: *"Petabytes of data require a distributed file system, so we created minikeyvalue instead of using any of the complex alternatives which have many features we have no use for."*

## Architecture (from README, verified)

```
Client → mkv master (Go, ~1000 lines, LevelDB index)
              → nginx volume servers (stock nginx, filesystem blob storage)
```

- The master server maps keys to volume servers using LevelDB.
- Volume servers are stock nginx serving files from a filesystem — no custom data-serving code.
- Replication: data is written to N volume servers simultaneously.
- The index (LevelDB) can be reconstructed from the volume servers via `rebuild`.
- Volumes can be added/removed via `rebalance`.

## Why it's interesting for this project

### 1. Energy-through-simplicity argument

minikeyvalue's ~1000-line codebase is orders of magnitude smaller than any SQL database (PostgreSQL: ~1.5M lines, MySQL: ~2M lines, MSSQL: closed but estimated millions). The energy implications:

- **Less code = less CPU work per request.** The Go master does a LevelDB lookup + HTTP 302 redirect. That's the entire per-request CPU cost. No query parser, no optimizer, no executor, no transaction manager.
- **nginx (C, event-driven) handles data transfer.** nginx is one of the most CPU-efficient HTTP servers ever built. Serving a 1 MB blob via nginx sendfile is near-zero CPU (DMA from disk to network).
- **LevelDB (C++) is highly optimized** for point lookups — single-digit microseconds per get.
- **No background processes.** No WAL replay, no checkpoint threads, no vacuum, no statistics collection. Idle power = process-scheduled-out = ~0 W for the master.

**Honest caveat:** No energy benchmark exists for minikeyvalue (confirmed via search). The energy argument is architectural reasoning, not measurement. The comma.ai blog emphasizes low *cost* ("used servers and slow spinning disks are cheap"), not low *energy*. Spinning disks are actually energy-hungry (~6-9 W idle per drive vs. ~0.1 W for NVMe), so minikeyvalue's production deployment may be higher-energy than an NVMe-based SQL engine for the same data.

### 2. Blob-storage layer for LOB columns

The DataMigrata source schema has several large LOB columns that dominate row width but are rarely queried:
- `HR.Employees.EmployeeData` (XML, variable)
- `HR.Employees.ProfilePicture` (varbinary(MAX))
- `Sales.Transactions.TransactionDetails` (nvarchar(MAX), JSON)
- `Sales.Transactions.Region` (geography)
- `Sales.Products.Specifications` (nvarchar(MAX))

These LOBs are ~95% of the scanned bytes in `HR.Employees` but are accessed by <10% of the 50 operations. In Section 3 Problem 3.4, we proposed moving LOBs to a "sparse side-table." minikeyvalue is a candidate for that side-table — it's purpose-built for large-blob storage with minimal overhead.

**Energy model for LOB side-table via minikeyvalue:**
- Analytical queries scan only the narrow columns (DuckDB columnar) = ~50 bytes/row × 15,000 rows = 750 KB DRAM read ≈ 9.4 mJ
- When a LOB is needed (ops 6-10 XML, 11-15 JSON, 31-35 spatial): one HTTP GET to minikeyvalue → nginx sendfile → ~1 mJ for the redirect + ~2 mJ for the blob transfer (NVMe DMA, near-zero CPU)
- Compare to current: scanning the LOB in-row costs ~1.3 J per HR.Employees scan (95% of 15 MB)
- **Potential saving: ~1.3 J → ~12 mJ per LOB-touching scan = ~100× reduction** (architectural estimate, unmeasured)

### 3. Migration transport layer

The DataMigrata migration compiler (Section 4) needs to move ~8 MB of data from MSSQL to the target engine. For the LOB subset (~7 MB of the 8 MB), minikeyvalue could serve as the bulk-transport layer:
- MSSQL → extract LOBs → PUT to minikeyvalue (parallel, streaming)
- minikeyvalue → GET → load into target engine's LOB side-table
- Energy: nginx sendfile is more energy-efficient than SQL-level BULK INSERT for large blobs (no transaction log, no WAL, no trigger overhead)

## Where it does NOT fit

1. **NOT a SQL engine candidate.** minikeyvalue has no SQL parser, no joins, no aggregations, no relational algebra. It cannot run any of the 50 operations. It is not in ClickBench, TPC-H, or any analytical benchmark.
2. **NOT a replacement for the target database.** It's a storage-layer component, not a query engine.
3. **NOT measured for energy.** No RAPL or power-meter data exists. All energy claims above are architectural estimates.
4. **NOT designed for energy efficiency.** comma.ai's deployment uses spinning disks (high idle power). The simplicity argument is about code complexity, not joules.

## Positioning in the Problem Catalogue

| Section | Role | Confidence |
|---|---|---|
| **Section 1 (Engine Selection)** | Not a candidate (no SQL) | N/A |
| **Section 2 (Operations)** | Not applicable (no query operators) | N/A |
| **Section 3 (Structures) — Problem 3.4** | **Candidate for LOB side-table storage layer.** Alternative to MSSQL's LOB off-row storage or DuckDB's blob extension. The ~1000-line architecture minimizes per-blob CPU overhead. | Low (0.35) — no energy measurement, architectural reasoning only |
| **Section 4 (Compiler) — Problem 4.4** | **Candidate for migration bulk-transport.** For LOB data movement, minikeyvalue's streaming PUT/GET may be more energy-efficient than SQL BULK INSERT. | Low (0.30) — no comparative measurement |
| **Source Data Quality Report** | Added to source catalogue as a verified source (GitHub repo + comma.ai blog + HN discussion). No energy data, but architecture is documented. | — |

## Sources (all verified HTTP 200 on 2026-07-28)

| # | Source | URL | What it provides |
|---|---|---|---|
| 1 | GitHub repo | https://github.com/geohot/minikeyvalue | README, architecture, API, ~3150 stars, MIT license |
| 2 | comma.ai blog | https://blog.comma.ai/scaling-for-10x-user-growth | Production usage context: petabytes, spinning disks, simplicity motivation |
| 3 | HN discussion | https://news.ycombinator.com/item?id=25642062 | Architecture critique: key→locateVolumeServer→lookupOnVolumeServerByKey |
| 4 | Shallow Brook Software | https://shallowbrooksoftware.com/posts/learning-from-geohots-minikeyvalue-project | Architecture analysis: HTTP interface, Python origin, design simplicity |
| 5 | rust-minikeyvalue | https://github.com/vrnvu/rust-minikeyvalue | Rust reimplementation, confirms architecture (HTTP, 1MB-1GB values) |

## Recommendation

**Include minikeyvalue in the knowledge base as a supplementary storage-layer candidate, positioned in Section 3 (Problem 3.4: LOB side-table) and Section 4 (Problem 4.4: migration transport).** Do NOT include it in the engine-selection ADR (Section 1) — it's not a SQL engine. The energy argument is architectural (simplicity → less CPU → potentially fewer joules) and unmeasured; flag it as a divergence variant with low confidence (0.30-0.35) that would require a custom RAPL measurement to validate.

**If we want to validate the energy claim:** run minikeyvalue vs. MSSQL LOB storage vs. DuckDB blob extension on a bare-metal server with RAPL, measuring joules per 1 MB blob GET. This is a 1-day experiment (~$5 on c6i.metal) and would either confirm or refute the simplicity→energy-efficiency hypothesis.
