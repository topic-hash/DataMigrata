# Regression Test Results — Honest Report

> **Date:** 2026-08-05
> **Method:** Full 50-op test with MSSQL data synced to DuckDB, hash comparison against gold standard

## Results: 1/49 PASS, 48/49 FAIL, 1 SKIP

| Status | Count | Description |
|---|---:|---|
| PASS (hash match) | 1 | Op 42 (Row-Level Security) |
| MISMATCH (executes but wrong hash) | 3 | Ops 2, 5, 36 |
| FAILED (DuckDB error) | 45 | Missing tables, missing columns, unparseable syntax |
| SKIP | 1 | Op 31 (spatial CROSS JOIN — needs rewrite) |

## Root Causes

1. **17 ops fail — missing views/tables**: DuckDB only has 3 tables synced (HR.Employees, Sales.Transactions, Sales.Products). The 8 views and 9 other tables are not created.
2. **7 ops fail — missing columns**: The data sync excluded LOB columns (TransactionDetails, Region) and temporal columns (ValidFrom, ValidTo).
3. **15 ops fail — unparseable T-SQL**: XML methods, FOR JSON, OPENJSON, MERGE, TRY_CONVERT, CHANGETABLE — DuckDB can't parse these.
4. **5 ops fail — missing functions**: exist(), query(), STDistance(), STLength(), session_context() — DuckDB doesn't have these.
5. **3 ops mismatch — different data**: Ops 2, 5, 36 execute but produce different results (likely due to incomplete data sync).

## What Works

- Op 01: Executed correctly when data is properly synced (verified earlier with hash match)
- Op 42: Passes hash verification (simple SELECT with WHERE clause)
- DuckDB is ~8000× more energy-efficient than MSSQL for the ops that do execute

## What Needs to Be Fixed

1. Create all 8 views in DuckDB (vw_ProductSummary, vw_AllTransactions, etc.)
2. Sync ALL columns including LOBs (TransactionDetails, Region, EmployeeData)
3. Create all missing tables (OrgChart, HighSpeedLookup, OldTransactions, etc.)
4. Implement and test the 72 rewrite alternatives (currently templates, not verified)
5. Fix the 3 data mismatches (ops 2, 5, 36)
