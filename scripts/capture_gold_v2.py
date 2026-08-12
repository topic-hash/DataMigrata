#!/usr/bin/env python3
"""
Capture gold standard CSVs from MSSQL - v2 with QUOTED_IDENTIFIER ON prefix.
"""
import os
import sys
import subprocess
import time
import hashlib

OPS_DIR = '/workspaces/DataMigrata/scripts/ops_individual'
OUT_DIR = '/workspaces/DataMigrata/gold_standard'

SQLCMD_BASE = [
    'docker', 'exec', '-i', 'mssql-test',
    '/opt/mssql-tools18/bin/sqlcmd',
    '-S', 'localhost', '-U', 'sa', '-P', 'YourStrong@Passw0rd',
    '-C', '-l', '60', '-t', '120',
    '-d', 'MSSQL_Advanced_Demo',
    '-I',  # quoted identifiers on
    '-W',  # trim trailing whitespace
    '-s', ',',  # column separator
    '-h', '-1',  # no headers
    '-w', '65535',  # wide rows
]

SET_PREFIX = "SET QUOTED_IDENTIFIER ON;\nSET ANSI_NULLS ON;\nSET ANSI_PADDING ON;\nSET ANSI_WARNINGS ON;\nSET CONCAT_NULL_YIELDS_NULL ON;\nSET NOCOUNT ON;\nGO\n"

def run_op(op_num, sql_text):
    cmd = SQLCMD_BASE.copy()
    full_sql = SET_PREFIX + sql_text
    start = time.time()
    try:
        proc = subprocess.run(
            cmd, input=full_sql.encode('utf-8'),
            capture_output=True, timeout=180
        )
        elapsed = time.time() - start
        return proc.stdout.decode('utf-8', errors='replace'), \
               proc.stderr.decode('utf-8', errors='replace'), \
               proc.returncode, elapsed
    except subprocess.TimeoutExpired:
        return '', 'TIMEOUT after 180s', 124, 180.0

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    summary = []
    for op_num in range(1, 51):
        op_file = os.path.join(OPS_DIR, f'op_{op_num:02d}.sql')
        if not os.path.exists(op_file):
            continue
        with open(op_file) as f:
            sql_text = f.read()
        print(f'--- OP {op_num:02d} ---', flush=True)
        stdout, stderr, exit_code, elapsed = run_op(op_num, sql_text)
        
        out_csv = os.path.join(OUT_DIR, f'op_{op_num:02d}.csv')
        cleaned_lines = []
        for line in stdout.splitlines():
            if line.startswith('Changed database context') or \
               line.startswith('Msg ') or \
               line.startswith('Cmd ') or \
               line.startswith('DBCC'):
                continue
            if line.strip().startswith('(') and 'rows affected)' in line:
                continue
            if line.strip().startswith('ALL 50') or line.strip().startswith('====='):
                continue
            cleaned_lines.append(line)
        
        while cleaned_lines and cleaned_lines[-1].strip() == '':
            cleaned_lines.pop()
        
        with open(out_csv, 'w') as f:
            f.write('\n'.join(cleaned_lines))
            if cleaned_lines:
                f.write('\n')
        
        with open(out_csv, 'rb') as f:
            content = f.read()
        hash_val = hashlib.md5(content).hexdigest()
        row_count = len(cleaned_lines)
        
        status = 'OK' if exit_code == 0 and row_count > 0 else ('NO_RESULTS' if row_count == 0 else 'FAIL')
        # If exit_code != 0 but we have rows, still mark OK
        if row_count > 0 and exit_code != 0:
            status = 'OK_WITH_WARNINGS'
        summary.append((op_num, status, row_count, hash_val, elapsed, stderr[:300].replace('\n', ' | ')))
        print(f'  {status}  rows={row_count}  hash={hash_val[:16]}  elapsed={elapsed:.2f}s', flush=True)
    
    with open(os.path.join(OUT_DIR, 'summary.csv'), 'w') as f:
        f.write('op_id,status,row_count,hash,elapsed_s,stderr\n')
        for op_num, status, rc, h, el, err in summary:
            f.write(f'{op_num},{status},{rc},{h},{el:.2f},"{err}"\n')
    
    ok = sum(1 for s in summary if s[1] in ('OK', 'OK_WITH_WARNINGS'))
    print(f'\n=== SUMMARY: {ok}/50 OK ===')

if __name__ == '__main__':
    main()
