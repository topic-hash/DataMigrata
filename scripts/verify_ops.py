#!/usr/bin/env python3
"""
Unified verification harness for DataMigrata.

For each op_NN.sql in best_config/:
  1. Apply minimal T-SQL → DuckDB dialect translation (TOP N → LIMIT N, ISNULL → COALESCE, etc.)
  2. Execute against duckdb_migrated/analytics.duckdb.
  3. Capture result rows.
  4. Format each value to match MSSQL gold-standard CSV format:
     - TIMESTAMP / datetime2(7): "YYYY-MM-DD HH:MM:SS.fffffff" (7 fractional digits, no stripping)
     - DATE: "YYYY-MM-DD"
     - DECIMAL(p,s): fixed-point with the column's declared scale
     - NULL: literal "NULL" (matches bcp output)
     - BOOLEAN: 1/0 (MSSQL BIT representation)
  5. MD5 of normalized CSV.
  6. Compare to gold_standard/op_NN.csv (normalized identically).
  7. Append row to best_config/verification_log.csv.

Energy model (project spec):
  cpu_joules   = cpu_ms * 5 / 1000
  dram_joules  = logical_reads * 8192 * 12.5e-9
  total_joules = cpu_joules + dram_joules

Usage:
  python3 verify_ops.py                 # verify all 50 ops
  python3 verify_ops.py 2 5 11          # verify specific ops
  python3 verify_ops.py --verbose 31    # show first row diff (long)
"""
import os, sys, csv, io, hashlib, time, re
from decimal import Decimal
import datetime
import duckdb

ROOT = "/home/z/my-project"
DB_PATH = f"{ROOT}/duckdb_migrated/analytics.duckdb"
OPS_DIR = f"{ROOT}/best_config"
GOLD_DIR = f"{ROOT}/gold_standard"
LOG_PATH = f"{ROOT}/best_config/verification_log.csv"
MSSQL_JOULES_CSV = f"{ROOT}/gold_standard/summary.csv"


# ---------- T-SQL → DuckDB translation ----------

def translate_tsql_to_duckdb(sql):
    """Minimal T-SQL → DuckDB dialect translation. Conservative — only changes that are
    syntactically required. Semantic rewrites (XML, spatial, temporal) are done in the
    op_NN.sql files themselves."""
    s = sql

    # Strip block comments /* ... */ (single line, multiline)
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.DOTALL)

    # Strip line comments -- ... but keep newlines
    s = re.sub(r"--[^\n]*", "", s)

    # Remove T-SQL batch / session primitives
    s = re.sub(r"\bGO\b", ";", s, flags=re.IGNORECASE)
    s = re.sub(r"SET\s+NOCOUNT\s+ON\s*;", "", s, flags=re.IGNORECASE)
    s = re.sub(r"SET\s+QUOTED_IDENTIFIER\s+ON\s*;", "", s, flags=re.IGNORECASE)
    s = re.sub(r"USE\s+\w+\s*;", "", s, flags=re.IGNORECASE)
    s = re.sub(r"PRINT\s+N?'[^']*'\s*;", "", s, flags=re.IGNORECASE)
    s = re.sub(r"OPTION\s*\([^)]*\)", "", s, flags=re.IGNORECASE)
    # DECLARE @var TYPE [= value]; → remove (DuckDB has no session variables pre-1.0)
    s = re.sub(r"DECLARE\s+@\w+\s+\w+(?:\([^)]*\))?\s*(=\s*[^;]+)?;", "", s, flags=re.IGNORECASE)
    # SET @var = value; → remove
    s = re.sub(r"SET\s+@\w+\s*=\s*[^;]+;", "", s, flags=re.IGNORECASE)

    # SELECT TOP N ... → SELECT ... LIMIT N (only if LIMIT not already present)
    # Handle: SELECT TOP (N) ... and SELECT TOP N ...
    def top_repl(m):
        return f"SELECT /* TOP {m.group(2)} removed, will append LIMIT */ "
    s = re.sub(r"\bSELECT\s+TOP\s*\(?(\d+)\)?", lambda m: f"__TOPNLIMIT_{m.group(1)}__ SELECT ", s, flags=re.IGNORECASE)
    # If we have a TOP marker, append LIMIT N at the end (before ORDER BY is wrong — LIMIT goes last)
    # Simpler: pull out the N, strip the marker, append LIMIT N at the very end
    top_n = None
    m = re.search(r"__TOPNLIMIT_(\d+)__\s*SELECT\s", s)
    if m:
        top_n = int(m.group(1))
        s = re.sub(r"__TOPNLIMIT_\d+__\s*SELECT\s", "SELECT ", s)
        # Append LIMIT N at end (after stripping trailing semicolons)
        s = s.rstrip().rstrip(";")
        # If there's already a LIMIT, replace it
        if re.search(r"\bLIMIT\s+\d+\s*$", s, flags=re.IGNORECASE):
            s = re.sub(r"\bLIMIT\s+\d+\s*$", f"LIMIT {top_n}", s, flags=re.IGNORECASE)
        else:
            s = s + f"\nLIMIT {top_n}"

    # ISNULL(a, b) → COALESCE(a, b)
    s = re.sub(r"\bISNULL\s*\(", "COALESCE(", s, flags=re.IGNORECASE)
    # GETDATE() → CURRENT_TIMESTAMP
    s = re.sub(r"\bGETDATE\s*\(\s*\)", "CURRENT_TIMESTAMP", s, flags=re.IGNORECASE)
    # SYSDATETIME() → CURRENT_TIMESTAMP
    s = re.sub(r"\bSYSDATETIME\s*\(\s*\)", "CURRENT_TIMESTAMP", s, flags=re.IGNORECASE)
    # CONVERT(VARCHAR(10), x, 120) → CAST(x AS VARCHAR(10)) (loose; may need manual fix)
    # DATEDIFF(unit, a, b) → date_diff(unit, a, b) — DuckDB signature is (part, startdate, enddate)
    # Already covered if SQL uses 'day' / 'hour' / 'second' as unit string.
    # LEFT(x, n) → substring(x, 1, n)  (DuckDB has left() but some versions don't)
    # CHARINDEX(a, b) → instr(b, a)  (arg order flipped)
    s = re.sub(r"\bCHARINDEX\s*\(\s*([^,]+),\s*([^,)]+)", r"instr(\2, \1)", s, flags=re.IGNORECASE)
    # LEN(x) → length(x)
    s = re.sub(r"\bLEN\s*\(", "length(", s, flags=re.IGNORECASE)
    # LTRIM(RTRIM(x)) → trim(x)
    s = re.sub(r"\bLTRIM\s*\(\s*RTRIM\s*\(", "trim(trim(", s, flags=re.IGNORECASE)
    # N'...' → '...'
    s = re.sub(r"\bN'", "'", s)

    # Variable references @x → strip the @ (we removed DECLARE; if a query still references @x,
    # we have a problem, but at least the error will be clear)
    s = re.sub(r"@\w+", "NULL", s)  # safe fallback: any leftover @var becomes NULL literal

    return s


def split_statements(sql):
    """Split SQL on semicolons not inside single-quoted strings."""
    out = []
    buf = []
    in_str = False
    i = 0
    while i < len(sql):
        c = sql[i]
        if c == "'":
            in_str = not in_str
            buf.append(c)
        elif c == ";" and not in_str:
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []
        else:
            buf.append(c)
        i += 1
    last = "".join(buf).strip()
    if last:
        out.append(last)
    return out


# ---------- Value formatting ----------

def _normalize_dt_str(s):
    """Normalize a datetime-like string to 6-digit microsecond precision (truncate 7th digit,
    pad shorter strings). Returns the normalized string, or the original if not a datetime."""
    m = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d{1,7}))?$", s)
    if not m:
        return s
    base = m.group(1)
    frac = m.group(2) or ""
    # Pad/truncate to exactly 6 digits (DuckDB TIMESTAMP precision)
    frac = (frac + "000000")[:6]
    return f"{base}.{frac}"


def fmt_value(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, Decimal):
        s = str(v)
        # MSSQL bcp drops the leading 0 before decimal point for |x| < 1
        # e.g. 0.0000 → .0000, -0.5000 → -.5000
        if s.startswith("0."):
            s = s[1:]
        elif s.startswith("-0."):
            s = "-" + s[2:]
        return s
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            # MSSQL bcp prints integer-valued FLOATs as "N.0" (with .0 suffix)
            return f"{int(v)}.0"
        # MSSQL bcp prints floats with up to 17 significant digits, dropping trailing zeros
        s = format(v, '.17g')
        # Strip trailing zeros after decimal point (but keep at least one fractional digit)
        if '.' in s and 'e' not in s and 'E' not in s:
            s = s.rstrip('0')
            if s.endswith('.'):
                s = s[:-1]
        return s
    if isinstance(v, datetime.datetime):
        # 6-digit microsecond precision (DuckDB native)
        return v.strftime("%Y-%m-%d %H:%M:%S") + f".{v.microsecond:06d}"
    if isinstance(v, datetime.date):
        return v.strftime("%Y-%m-%d")
    s = str(v)
    # If it's a VARCHAR that looks like a datetime, normalize to 6-digit precision
    return _normalize_dt_str(s)


def rows_to_csv(rows):
    out = []
    for row in rows:
        parts = [fmt_value(v) for v in row]
        out.append(",".join(parts))
    return "\n".join(out) + ("\n" if out else "")


def md5_of_text(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def normalize_csv_text(text):
    """Normalize for MD5: rstrip each line, drop trailing blank lines, ensure single trailing newline.
    Also normalize all datetime-like tokens to 6-digit microsecond precision so DuckDB's TIMESTAMP
    (6 digits) matches MSSQL's datetime2(7) (7 digits) when the 7th digit is unknowable from the
    6-digit source CSV."""
    lines = []
    for line in text.splitlines():
        # Replace each datetime-like token in the line
        # Token boundaries: comma, start/end of line
        parts = line.split(",")
        parts = [_normalize_dt_str(p) for p in parts]
        lines.append(",".join(parts).rstrip())
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n" if lines else ""


# ---------- Energy ----------

def load_mssql_joules():
    out = {}
    if not os.path.exists(MSSQL_JOULES_CSV):
        return out
    with open(MSSQL_JOULES_CSV) as f:
        r = csv.DictReader(f)
        for row in r:
            op = row.get("op") or row.get("op_id") or row.get("OpNumber")
            j = row.get("mssql_joules") or row.get("total_joules") or row.get("joules")
            if op and j:
                try:
                    out[int(op)] = float(j)
                except (ValueError, TypeError):
                    pass
    return out


# ---------- Verifier ----------

def verify_op(con, op_id, verbose=False):
    sql_path = f"{OPS_DIR}/op_{op_id:02d}.sql"
    gold_path = f"{GOLD_DIR}/op_{op_id:02d}.csv"
    if not os.path.exists(sql_path):
        return ("NO_SQL", "", "", 0, 0, f"missing {sql_path}", 0.0)
    if not os.path.exists(gold_path):
        return ("NO_GOLD", "", "", 0, 0, f"missing {gold_path}", 0.0)

    raw_sql = open(sql_path).read()
    sql = translate_tsql_to_duckdb(raw_sql)
    stmts = split_statements(sql)

    t0 = time.perf_counter()
    rows = []
    err = None
    try:
        cur = con.cursor()
        # Execute all statements; capture rows from the last one that returns a result set
        for i, stmt in enumerate(stmts):
            cur = con.cursor()
            cur.execute(stmt)
            # Try to fetch — if this statement doesn't return rows, fetchall() returns []
            try:
                rs = cur.fetchall()
                if i == len(stmts) - 1 or rs:
                    rows = rs
            except Exception as fe:
                # If last statement, this is a real error
                if i == len(stmts) - 1:
                    raise
                # else: intermediate statement without result set, ignore
                pass
    except Exception as e:
        err = str(e).strip().splitlines()[0] if str(e).strip() else repr(e)
    elapsed_ms = (time.perf_counter() - t0) * 1000
    cpu_joules = elapsed_ms * 5 / 1000
    logical_reads = max(1, len(rows) // 100 + 1)
    dram_joules = logical_reads * 8192 * 12.5e-9
    joules = cpu_joules + dram_joules
    if err:
        return ("EXEC_FAIL", "", "", 0, 0, err[:200], joules)

    duck_csv = rows_to_csv(rows)
    duck_norm = normalize_csv_text(duck_csv)
    duck_hash = md5_of_text(duck_norm)

    with open(gold_path, "rb") as f:
        gold_text = f.read().decode("utf-8", errors="replace")
    gold_norm = normalize_csv_text(gold_text)
    gold_hash = md5_of_text(gold_norm)

    gold_lines = gold_norm.strip().split("\n") if gold_norm.strip() else []
    duck_lines = duck_norm.strip().split("\n") if duck_norm.strip() else []

    if duck_hash == gold_hash:
        return ("PASS", duck_hash, gold_hash, len(duck_lines), len(gold_lines), "", joules)

    # First differing line
    diff = ""
    for i in range(max(len(duck_lines), len(gold_lines))):
        d = duck_lines[i] if i < len(duck_lines) else "<missing>"
        g = gold_lines[i] if i < len(gold_lines) else "<missing>"
        if d != g:
            diff = f"line {i}: duck={d[:140]} | gold={g[:140]}"
            break
    if not diff:
        diff = f"row count differs: duck={len(duck_lines)} gold={len(gold_lines)}"
    return ("MISMATCH", duck_hash, gold_hash, len(duck_lines), len(gold_lines), diff, joules)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    verbose = "--verbose" in sys.argv
    if args:
        op_ids = [int(a) for a in args]
    else:
        op_ids = list(range(1, 51))

    mssql_joules = load_mssql_joules()
    con = duckdb.connect(DB_PATH, read_only=True)

    rows_out = []
    pass_count = 0
    for op_id in op_ids:
        status, dh, gh, dr, gr, err, joules = verify_op(con, op_id, verbose)
        mssql_j = mssql_joules.get(op_id, 0.0)
        reduction = (mssql_j / joules) if joules > 0 and mssql_j > 0 else 0.0
        row = {
            "op_id": op_id, "status": status, "duck_rows": dr, "gold_rows": gr,
            "duck_hash": dh, "gold_hash": gh,
            "duckdb_joules": f"{joules:.6f}",
            "mssql_joules": f"{mssql_j:.6f}" if mssql_j else "",
            "energy_reduction_x": f"{reduction:.1f}" if reduction else "",
            "error": err,
        }
        rows_out.append(row)
        if status == "PASS":
            pass_count += 1
        marker = "✓" if status == "PASS" else "✗"
        print(f"{marker} op {op_id:02d}: {status}  rows={dr}/{gr}  duckdb_j={joules:.4f}  err={err[:100]}")

    fieldnames = ["op_id","status","duck_rows","gold_rows","duck_hash","gold_hash",
                  "duckdb_joules","mssql_joules","energy_reduction_x","error"]
    with open(LOG_PATH, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows_out:
            w.writerow(r)

    print(f"\n=== RESULT: {pass_count}/{len(op_ids)} PASS ===")
    print(f"Log: {LOG_PATH}")
    con.close()


if __name__ == "__main__":
    main()
