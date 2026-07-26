#!/usr/bin/env python3
"""
Split 02_MSSQL_50_Operations_Expanded.sql into individual op files,
then execute each one against the running MSSQL Docker container.

For each op:
  - Capture exit code, stdout, stderr, row count, elapsed time
  - Save individual op log to results/op_NN.log
  - Aggregate everything to results/batch_summary.json

Usage:
  python3 split_and_run.py [--start N] [--end N] [--out DIR]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path("/workspaces/DataMigrata")
SQL_FILE = REPO_ROOT / "sql" / "02_MSSQL_50_Operations_Expanded.sql"
SCHEMA_FILE = REPO_ROOT / "sql" / "00_COMPLETE_MSSQL_Deployment.sql"
POPULATE_FILE = REPO_ROOT / "sql" / "populate_employees.sql"
OP_DIR = REPO_ROOT / "scripts" / "ops_individual"
RESULTS_DIR = REPO_ROOT / "scripts" / "results"

SQLCMD = [
    "docker", "exec", "-i", "mssql-advanced-demo",
    "/opt/mssql-tools18/bin/sqlcmd",
    "-S", "localhost",
    "-U", "sa",
    "-P", "YourStrong@Passw0rd",
    "-C",  # trust server cert
    "-b",  # error -> exit code 1
    "-l", "60",  # login timeout
    "-t", "300",  # query timeout 5min
    "-I",  # quoted identifiers on
    "-W",  # trim trailing whitespace
    "-s", ",",  # column separator
    "-h", "-1",  # no headers
]


OP_HEADER_RE = re.compile(r"^--\s*OP\s+(\d+)\s*:", re.MULTILINE)


def split_ops() -> list[tuple[int, str]]:
    """Return [(op_num, op_sql), ...] in order."""
    text = SQL_FILE.read_text(encoding="utf-8")
    # find all OP N: header positions
    matches = list(OP_HEADER_RE.finditer(text))
    if not matches:
        raise RuntimeError("No -- OP N: headers found")
    ops = []
    for i, m in enumerate(matches):
        op_num = int(m.group(1))
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        chunk = text[start:end]
        ops.append((op_num, chunk))
    return ops


def write_op_files(ops: list[tuple[int, str]]) -> None:
    OP_DIR.mkdir(parents=True, exist_ok=True)
    for op_num, sql in ops:
        path = OP_DIR / f"op_{op_num:02d}.sql"
        path.write_text(sql, encoding="utf-8")


def exec_op(op_num: int, sql: str) -> dict:
    """Execute a single op via docker exec sqlcmd. Returns result dict."""
    # sqlcmd needs the file piped in. Use stdin.
    cmd = SQLCMD + ["-d", "MSSQL_Advanced_Demo"]
    start = time.time()
    try:
        proc = subprocess.run(
            cmd,
            input=sql,
            capture_output=True,
            text=True,
            timeout=600,
        )
        exit_code = proc.returncode
        stdout = proc.stdout
        stderr = proc.stderr
    except subprocess.TimeoutExpired:
        return {
            "op": op_num,
            "status": "TIMEOUT",
            "exit_code": 124,
            "elapsed_s": 600.0,
            "stdout": "",
            "stderr": "TIMEOUT after 600s",
        }
    elapsed = time.time() - start

    # parse row count from stdout: sqlcmd prints "(N rows affected)" as final line
    row_count = None
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        m = re.match(r"\((\d+) rows? affected\)", line)
        if m:
            row_count = int(m.group(1))
            break

    return {
        "op": op_num,
        "status": "PASS" if exit_code == 0 else "FAIL",
        "exit_code": exit_code,
        "elapsed_s": round(elapsed, 2),
        "row_count": row_count,
        "stdout": stdout[-2000:] if len(stdout) > 2000 else stdout,
        "stderr": stderr[-3000:] if len(stderr) > 3000 else stderr,
    }


def deploy_schema_and_data() -> tuple[bool, str]:
    """Run the schema deployment + populate script. Return (success, log)."""
    log_parts = []

    # 1. Deploy complete schema (creates DB + tables + views + procs + fn + data)
    log_parts.append("=== DEPLOY: 00_COMPLETE_MSSQL_Deployment.sql ===")
    cmd = SQLCMD[:-3]  # drop -s/-h/-1/-W (use defaults for deployment)
    # Note: no -b flag here. Schema deployment contains optional steps
    # (full-text catalog/index) that fail when FTS is not installed in the
    # container. Those failures are acceptable; we want deployment to continue.
    cmd = ["docker", "exec", "-i", "mssql-advanced-demo",
           "/opt/mssql-tools18/bin/sqlcmd",
           "-S", "localhost", "-U", "sa", "-P", "YourStrong@Passw0rd",
           "-C", "-l", "60", "-t", "600"]
    proc = subprocess.run(cmd, input=SCHEMA_FILE.read_bytes(),
                          capture_output=True, timeout=900)
    log_parts.append(f"exit={proc.returncode}")
    if proc.stdout:
        log_parts.append(proc.stdout.decode("utf-8", errors="replace")[-2000:])
    if proc.stderr:
        log_parts.append("STDERR: " + proc.stderr.decode("utf-8", errors="replace")[-2000:])
    if proc.returncode != 0:
        return False, "\n".join(log_parts)

    # 2. Populate employees
    log_parts.append("\n=== POPULATE: populate_employees.sql ===")
    proc = subprocess.run(cmd, input=POPULATE_FILE.read_bytes(),
                          capture_output=True, timeout=900)
    log_parts.append(f"exit={proc.returncode}")
    if proc.stdout:
        log_parts.append(proc.stdout.decode("utf-8", errors="replace")[-2000:])
    if proc.stderr:
        log_parts.append("STDERR: " + proc.stderr.decode("utf-8", errors="replace")[-2000:])
    return proc.returncode == 0, "\n".join(log_parts)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--start", type=int, default=1)
    p.add_argument("--end", type=int, default=50)
    p.add_argument("--out", type=str, default=str(RESULTS_DIR))
    p.add_argument("--skip-deploy", action="store_true",
                   help="Skip schema+data deployment (assume DB already ready)")
    args = p.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    ops = split_ops()
    print(f"Split {len(ops)} operations")
    write_op_files(ops)

    if not args.skip_deploy:
        ok, log = deploy_schema_and_data()
        (out_dir / "deploy.log").write_text(log, encoding="utf-8")
        if not ok:
            print("DEPLOY FAILED — see deploy.log")
            print(log[-1500:])
            return 2
        print("Deploy OK")

    results = []
    for op_num, sql in ops:
        if op_num < args.start or op_num > args.end:
            continue
        print(f"--- OP {op_num:02d} ---")
        res = exec_op(op_num, sql)
        results.append(res)
        (out_dir / f"op_{op_num:02d}.log").write_text(
            f"=== OP {op_num} ===\n"
            f"STATUS: {res['status']}  exit={res['exit_code']}  "
            f"elapsed={res['elapsed_s']}s  rows={res.get('row_count')}\n\n"
            f"--- STDERR ---\n{res['stderr']}\n\n"
            f"--- STDOUT (tail) ---\n{res['stdout']}\n",
            encoding="utf-8",
        )
        print(f"  {res['status']}  exit={res['exit_code']}  "
              f"elapsed={res['elapsed_s']}s  rows={res.get('row_count')}")
        if res["status"] == "FAIL":
            # show first error line
            for line in res["stderr"].splitlines():
                if "Msg" in line:
                    print(f"  ERROR: {line}")
                    break

    summary = {
        "total": len(results),
        "passed": sum(1 for r in results if r["status"] == "PASS"),
        "failed": sum(1 for r in results if r["status"] == "FAIL"),
        "timeouts": sum(1 for r in results if r["status"] == "TIMEOUT"),
        "results": results,
    }
    (out_dir / "batch_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8")
    print(f"\n=== SUMMARY: {summary['passed']}/{summary['total']} PASS, "
          f"{summary['failed']} FAIL, {summary['timeouts']} TIMEOUT ===")
    print(f"Results: {out_dir}/batch_summary.json")
    return 0 if summary["failed"] == 0 and summary["timeouts"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
