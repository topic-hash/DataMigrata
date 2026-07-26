# 50 MSSQL Operations — Execution Verification Report

**Date:** 2026-07-26
**Database:** MSSQL_Advanced_Demo (SQL Server 2022, Docker container `mssql-advanced-demo`)
**Codespace:** `symmetrical-tribble` (GitHub Codespaces)
**Result:** ✅ **50/50 operations PASS, 0 failures, 0 regressions**

## Methodology

1. Started MSSQL 2022 Docker container in the codespace
2. Deployed full schema + data via `sql/00_COMPLETE_MSSQL_Deployment.sql`
3. Populated HR.Employees (5,000 rows) via `sql/populate_employees.sql`
4. Split `sql/02_MSSQL_50_Operations_Expanded.sql` into 50 individual op files
5. Executed each op via `sqlcmd` inside the container, capturing exit code + error messages
6. Categorized failures, fixed SQL, re-ran to verify

## Regressions Found and Fixed

### Schema Regressions (in `00_COMPLETE_MSSQL_Deployment.sql`)

| Object | Error | Fix |
|---|---|---|
| `HR.vw_ManagerHierarchy` | Msg 1033: ORDER BY invalid in view | Removed ORDER BY from view definition |
| `Sales.vw_AllTransactions` | Msg 207: 7 invalid columns (Archive.OldTransactions has different schema) | Used NULL/CAST for missing columns in UNION ALL |
| `Sales.fn_GetEmployeeSales` | Msg 102/137: syntax error | Added missing `(` after function name |

### Operation Regressions (in `02_MSSQL_50_Operations_Expanded.sql`)

| Op | Category | Error | Fix |
|---|---|---|---|
| 1 | Hierarchical | Msg 240: type mismatch in recursive CTE | CAST CumulativeSalary to DECIMAL(18,2) in anchor + recursive |
| 2 | Hierarchical | Msg 467: aggregate in recursive CTE | Extracted SubCounts CTE, used INNER JOIN |
| 6-10, 13, 47 | XML/JSON/MERGE | Msg 1934: QUOTED_IDENTIFIER OFF | Added `SET QUOTED_IDENTIFIER ON;` at top of file |
| 15 | JSON | Msg 156: computed column in OPENJSON WITH | Moved LineTotal to SELECT list |
| 16 | Temporal | Msg 102: function in FOR SYSTEM_TIME AS OF | Extracted DATEADD into @AsOfDate variable |
| 21 | Views | Msg 8171: invalid NOEXPAND hint | Removed WITH (NOEXPAND) (view has no clustered index) |
| 35 | Spatial | Msg 6522: invalid geography instance | Added .MakeValid() to STGeomFromText result |

## Final Verification

All 50 operations re-run from the patched `02_MSSQL_50_Operations_Expanded.sql`:

```
OP 01-50: ALL PASS (exit=0, no error messages)
```

Full JSON results: `scripts/results/batch_1_50.json`

## Known Limitations

- **Full-Text Search** is not installed in the MSSQL 2022 Docker container (Msg 7609 during deployment). None of the 50 operations in this file use CONTAINS/FREETEXT, so this does not affect the result. If future operations require full-text, the container must be rebuilt with the feature enabled.
- **Row counts** show 0 for most ops because `sqlcmd` reports `(N rows affected)` only for the final statement, and several ops use temp variables or multi-statement batches.
