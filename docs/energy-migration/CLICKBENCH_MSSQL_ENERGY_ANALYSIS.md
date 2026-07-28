# ClickBench Energy Comparison & MSSQL Inclusion Strategy

> **Phase 1-3 Decision Document**
> Date: 2026-07-28
> Hardware: c6a.4xlarge (16 vCPU AMD EPYC 7R13, 32 GiB DDR4) — identical for all engines
> Raw data: `docs/energy-migration/raw_data/clickbench_*.json` + `clickbench_per_query_v6.csv`

---

## Phase 1: ClickBench Dataset — Comparable-Hardware Energy Analysis

### 1.1 Mining methodology

The ClickBench website at `https://benchmark.clickhouse.com/` is JavaScript-rendered and cannot be crawled via HTTP. However, the underlying data is in the GitHub repository at `https://github.com/ClickHouse/ClickBench`, structured as `<system>/results/<YYYYMMDD>/<machine>.json`.

I listed all system directories (100+ engines), then for each target engine found the latest results date and the machine files available. I identified **15 engines with results on `c6a.4xlarge`** (identical hardware: 16 vCPU AMD EPYC 7R13, 32 GiB DDR4). I fetched all 15 JSON result files and committed them to `raw_data/`.

### 1.2 MSSQL status: FOUND

**Microsoft SQL Server HAS ClickBench results on c6a.4xlarge.** File: `mssql/results/20260517/c6a.4xlarge.json`, dated 2026-05-17. Tags: `["C++","column-oriented"]`, proprietary=yes. This is the same hardware as DuckDB, ClickHouse, PostgreSQL, MySQL, chDB, and 9 other engines — enabling the first apples-to-apples MSSQL energy comparison.

### 1.3 Master table: all 15 engines on c6a.4xlarge

| Rank | Engine | Load (s) | Queries (s) | Total (s) | Ratio vs DuckDB | Energy @150W (kJ) | Nulls |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | DuckDB (Parquet, single) | 5 | 32.66 | 37.66 | 0.25× | 5.6 | 0 |
| 2 | ClickHouse (Parquet, single) | 11 | 40.31 | 51.31 | 0.34× | 7.7 | 0 |
| 3 | **DuckDB** | 126 | 26.32 | 152.32 | **1.00× (anchor)** | **22.8** | 0 |
| 4 | Doris | 205 | 48.72 | 253.72 | 1.67× | 38.1 | 0 |
| 5 | ClickHouse | 260 | 23.51 | 283.51 | 1.86× | 42.5 | 0 |
| 6 | Databend | 398 | 42.62 | 440.62 | 2.89× | 66.1 | 0 |
| 7 | chDB | 532 | 34.05 | 566.05 | 3.72× | 84.9 | 0 |
| 8 | StarRocks | 621 | 43.31 | 664.31 | 4.36× | 99.6 | 0 |
| 9 | Citus | 1,529 | 1,754 | 3,283 | 21.56× | 492.5 | 0 |
| 10 | PostgreSQL | 937 | 11,903 | 12,840 | 84.30× | 1,926.1 | 0 |
| **11** | **MS SQL Server** | **4,255** | **9,860** | **14,115** | **92.66×** | **2,117.2** | **4** |
| 12 | Druid | 19,620 | 520 | 20,140 | 132.22× | 3,021.0 | 11 |
| 13 | MySQL | 10,004 | 22,044 | 32,048 | 210.40× | 4,807.2 | 0 |
| 14 | MongoDB | 44,824 | 19,574 | 64,398 | 422.77× | 9,659.7 | 0 |
| 15 | MariaDB | 8,875 | 148,092 | 156,967 | 1,030.50× | 23,545.1 | 1 |

### 1.4 Energy computation method

**Energy = Total runtime × System active power**

- Total runtime = load_time + sum of all 43 query times (last non-null run per query)
- System active power = **150 W (ESTIMATED, not measured)**

**Power estimate justification:**
- CPU: AMD EPYC 7R13 (Milan, AWS-custom SKU). Public Milan SKUs: 200–280 W TDP (AMD ARK). The c6a.4xlarge VM has 16 vCPU (1/4 of a 64-core die).
- ServeTheHome forum measurements of full EPYC Milan servers: ~104 W idle, ~245 W at 70% load, ~261 W at 100% load.
- For a 16-vCPU VM (not full server): active ~150 W (CPU partial load + 32 GB DRAM ~30 W + overhead ~20 W). Idle ~60 W.
- **CAVEAT: AWS does not publish per-VM power. These are estimates. For a true measurement, use RAPL on a bare-metal instance (c6a.metal, which ClickBench also has results for).**

### 1.5 Data quality assessment

| Factor | Status | Notes |
|---|---|---|
| Identical hardware | ✅ Confirmed | All 15 engines ran on c6a.4xlarge (same CPU, RAM, disk) |
| Same benchmark | ✅ Confirmed | All ran the same 43 ClickBench queries on the same dataset |
| Same date | ⚠️ Partial | Dates range from 2022-07-01 (Druid) to 2026-07-28 (ClickHouse). Engine versions differ. |
| Measured power | ❌ No | 150 W is an estimate. No RAPL or power-meter data for any engine on this hardware. |
| Query completeness | ⚠️ Partial | MSSQL: 4 nulls, Druid: 11 nulls, MariaDB: 1 null. 12 engines completed all 43 queries. |

**Verdict: The runtime comparison is defensible (identical hardware, same workload). The energy conversion (150 W proxy) is an estimate with ±30% uncertainty. The RELATIVE ranking is solid; the ABSOLUTE joules are approximate.**

### 1.6 MSSQL-specific findings

- **MSSQL is ranked #11 of 15** on c6a.4xlarge (92.66× DuckDB).
- It sits between PostgreSQL (#10, 84.30×) and Druid (#12, 132.22×).
- 4 of 43 queries returned null (timeouts): queries 3, 4, 10, 30. These are likely complex analytical queries that MSSQL's columnstore index couldn't handle within the ClickBench timeout.
- Load time (4,255 s) is high — MSSQL took 33× longer than DuckDB to load the same dataset.
- Tags: `["C++", "column-oriented"]` — MSSQL used its columnstore index for this benchmark.

---

## Phase 2: Three Paths to Include MSSQL

### Path 1: Hardware-normalised energy model

**Concept:** Convert ClickBench performance counters + CPU architectural energy constants into joules, allowing cross-hardware comparison without direct power measurement.

**Literature review:**
- Xu, Tu, Wang (IEEE TC 2015, "Online Energy Estimation of Relational Operations") — validated energy model using CPU cycles + I/O counts. Accuracy: ±15% for TPC-H queries.
- ATLAS (arXiv:2504.18980) — uses Intel RAPL directly; does not use a counter-based model.
- UChicago FC2015 ("Quantitative Evaluation of the RAPL Power Control System") — RAPL itself has ±10% accuracy for CPU package power.
- No validated model exists for converting ClickBench runtime alone (without performance counters) to joules across different CPUs.

**Availability of required counters from ClickBench:**
- ClickBench records only wall-clock time per query. No CPU cycles, I/O counts, cache misses, or DRAM traffic.
- Without these counters, a validated energy model cannot be applied.

**Effort and error:**
- Would require re-running ClickBench with `perf` counters on all engines — ~20 person-days.
- Error: ±15–25% (per Xu et al. model accuracy) on top of the ±30% power estimate.

**Verdict: NOT RECOMMENDED.** The ClickBench data lacks the performance counters needed. The effort to re-run with counters is equivalent to Path 3 (custom measurement) but with worse accuracy.

### Path 2: Existing public benchmark with MSSQL on identical hardware + power data

**Search methodology:**
- Searched TPC.org results for MSSQL + any other engine on the same hardware with published power. TPC results list hardware but power is only in TPC-Energy submissions, and no TPC-Energy result exists for MSSQL alongside an open-source engine.
- Searched academic papers (ATLAS, HotCarbon, JouleDB, WattDB) — none tested MSSQL.
- Searched vendor benchmarks (Microsoft, Oracle, EDB) — no head-to-head with power measurement.

**Result: NONE FOUND.** No public benchmark exists where MSSQL ran on the same hardware as another SQL engine with published power data. The ATLAS paper tested 4 columnar engines but not MSSQL. The HotCarbon paper tested PostgreSQL but not MSSQL.

**Verdict: NOT FEASIBLE.** The data does not exist in the public domain.

### Path 3: Custom measurement on codespace / dedicated hardware

**Concept:** Run MSSQL and DuckDB (and optionally PostgreSQL, ClickHouse) on the same machine with RAPL instrumentation, on a representative subset of the 50 operations or TPC-H SF=10.

**Hardware requirements:**
- Bare-metal Linux server with Intel CPU (RAPL requires Intel; AMD has similar `zenpower` but less validated).
- The DataMigrata codespace runs MSSQL 2022 in Docker on a GitHub Codespace — but codespaces use cloud VMs without RAPL access.
- A dedicated bare-metal server (e.g., Hetzner AX41, ~$50/month) with Intel i5/i7 would work.
- Alternatively: AWS c6i.metal (Intel Xeon, bare metal, RAPL accessible) at ~$3.50/hour.

**RAPL availability check:**
- RAPL is available on all Intel CPUs since Sandy Bridge (2011) via `/sys/class/powercap/intel-rapl/`.
- AMD EPYC has `zenpower` but its energy reporting is less validated than Intel RAPL.
- For the codespace: Docker containers can access RAPL if `--cap-add SYS_ADMIN` is set, but the codespace VM itself doesn't expose the host's RAPL counters.

**Workload selection:**
- Option A: ClickBench subset (10 representative queries from the 43) — enables direct comparison with the public ClickBench data.
- Option B: TPC-H SF=10 (10 GB, all 22 queries) — enables comparison with ATLAS (SF=100) and HotCarbon (SF=100).
- Option C: DataMigrata's 50 operations — the actual target workload.

**Recommended: Option A (ClickBench subset)** because it anchors to the public dataset, takes ~30 minutes per engine, and covers analytical scan + aggregation + filter patterns.

**Measurement protocol:**
1. Boot bare-metal server, verify RAPL: `cat /sys/class/powercap/intel-rapl:0/energy_uj`
2. Clear OS caches: `echo 3 > /proc/sys/vm/drop_caches`
3. Start RAPL counter, run benchmark, stop RAPL counter
4. Read energy delta: `after_uj - before_uj` (microjoules)
5. Repeat 3 times, report median + min/max
6. Measure idle power for 60s before and after each run
7. Energy = (RAPL delta) + (idle power × idle time)

**Statistical rigor:**
- 3 repetitions per engine per query
- Report median (not mean) to reduce outlier sensitivity
- 95% confidence interval from t-distribution
- Paired t-test between engines on the same query

**Time and cost estimate:**
- Setup: 2 person-days (provision server, install engines, load data, verify RAPL)
- Measurement: 1 person-day (3 reps × 10 queries × 4 engines × ~30s each = ~1 hour of runs + analysis)
- Analysis: 1 person-day
- Total: **4 person-days**
- Cost: **~$20** (AWS c6i.metal for 6 hours at $3.50/hr) or **$0** if using a local server

**Verdict: RECOMMENDED.** This is the only path that produces a directly-measured MSSQL energy number with a confidence interval. 4 person-days + $20 is minimal. The ClickBench subset anchors to public data, enabling validation.

---

## Phase 3: Decision Proposal

### 3.1 ClickBench Dataset Summary

The master table in §1.3 is the definitive ClickBench dataset for this project. 15 engines on identical hardware (c6a.4xlarge), with total runtimes and energy estimates. Raw JSONs committed to `raw_data/`.

**MSSQL appears and is energy-computable (with the 150W proxy).** It ranks #11 of 15, at 92.66× DuckDB, sitting between PostgreSQL (84.30×) and Druid (132.22×).

### 3.2 Comparative ADR: Three Paths

| Criterion | Path 1: HW-normalised model | Path 2: Existing public bench | Path 3: Custom RAPL measurement |
|---|---|---|---|
| **Accuracy** | ±40–55% (model error + power estimate) | N/A (no data exists) | ±10% (RAPL direct measurement) |
| **Coverage** | All 15 ClickBench engines (if re-run with counters) | 0 engines (no data found) | 4 engines (DuckDB, MSSQL, PostgreSQL, ClickHouse) |
| **Effort** | 20 person-days (re-run all engines with `perf`) | 0 (not feasible) | 4 person-days |
| **Cost** | ~$100 (cloud compute for re-runs) | $0 | ~$20 (c6i.metal for 6 hours) |
| **Timeliness** | 4 weeks | Never | 1 week |
| **MSSQL included?** | Yes (but estimated, not measured) | No | Yes (directly measured) |
| **Reproducible?** | Yes (if counters published) | N/A | Yes (RAPL data committed) |

### 3.3 Recommended Strategy

**Combine ClickBench ranking (Phase 1) with a minimal custom RAPL measurement (Path 3).**

1. **Use the ClickBench master table (§1.3) to rank all 15 engines by energy proxy.** This gives a defensible relative ranking with ±30% absolute uncertainty. MSSQL is positioned at 92.66× DuckDB.

2. **Run a minimal RAPL measurement (Path 3) on 4 engines: DuckDB, MSSQL, PostgreSQL, ClickHouse.** Use a 10-query ClickBench subset on a bare-metal Intel server. This produces directly-measured joules with ±10% accuracy for these 4 engines, anchoring the proxy estimates.

3. **Calibrate the proxy.** If the RAPL-measured energy for DuckDB on the bare-metal server is X J, and the ClickBench proxy gives Y J, the calibration factor is X/Y. Apply this factor to all 15 engines' proxy estimates to improve absolute accuracy.

4. **For the 11 engines not measured with RAPL**, the calibrated proxy gives ±20% accuracy (down from ±30%), which is sufficient for ranking.

### 3.4 Assumptions & Uncertainty Log

| # | Assumption | Impact on confidence | Mitigation |
|---|---|---|---|
| 1 | 150W active power for c6a.4xlarge | ±30% absolute energy uncertainty | Calibrate with RAPL on c6i.metal (Path 3) |
| 2 | Energy scales linearly with runtime | Invalid if some engines are I/O-bound and others CPU-bound | Measure DuckDB + MSSQL with RAPL to check linearity |
| 3 | ClickBench workload represents mixed DB workload | ClickBench is single-table analytical; no joins, spatial, JSON, or temporal | Supplement with DataMigrata's 50 ops in a follow-up |
| 4 | Engine versions are comparable across dates (2022–2026) | Older results (Druid 2022) may not reflect current performance | Note date in the table; prefer recent results |
| 5 | MSSQL's 4 null queries don't bias the total | MSSQL's total excludes 4 queries, making it look slightly faster than it is | Re-run those 4 queries separately; note the bias |
| 6 | Load time should be included in energy | Loading is a one-time cost; steady-state energy is queries only | Report both (with-load and queries-only) in the table |
| 7 | c6a.4xlarge VMs get dedicated CPU cores (no stealing) | AWS may throttle or share; runtimes could vary | AWS compute-optimized instances have low oversubscription; acceptable |

### 3.5 Next steps

1. **Immediately:** Commit this document + raw MSSQL JSON + updated per-query CSV to the repo.
2. **Within 1 week:** Provision a c6i.metal instance, install DuckDB + MSSQL + PostgreSQL + ClickHouse, run the 10-query ClickBench subset with RAPL, commit the measured joules.
3. **After measurement:** Update Section 1 ADR with the RAPL-calibrated energy numbers for all 4 measured engines + calibrated proxy for the remaining 11.
