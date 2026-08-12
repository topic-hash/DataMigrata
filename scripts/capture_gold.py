#!/usr/bin/env python3
"""
Capture gold standard CSVs from MSSQL by running each op via sqlcmd.
This runs INSIDE the codespace via codespacectl. We pass it through stdin.

Approach: this script is uploaded to the codespace and run there.
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
    '-C', '-l', '60', '-t', '300',
    '-d', 'MSSQL_Advanced_Demo',
    '-W',  # trim trailing whitespace
    '-s', ',',  # column separator
    '-h', '-1',  # no headers
    '-w', '65535',  # wide rows
    '-r', '1',  # stderr messages
]

def run_op(op_num, sql_text):
    """Run op and return (stdout, stderr, exit_code, elapsed)."""
    cmd = SQLCMD_BASE.copy()
    # remove GO statements - sqlcmd handles them as batch separators natively,
    # but we want to keep them so multi-statement ops work
    start = time.time()
    try:
        proc = subprocess.run(
            cmd, input=sql_text.encode('utf-8'),
            capture_output=True, timeout=300
        )
        elapsed = time.time() - start
        return proc.stdout.decode('utf-8', errors='replace'), \
               proc.stderr.decode('utf-8', errors='replace'), \
               proc.returncode, elapsed
    except subprocess.TimeoutExpired:
        return '', 'TIMEOUT after 300s', 124, 300.0

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
        
        # Save raw output as CSV
        out_csv = os.path.join(OUT_DIR, f'op_{op_num:02d}.csv')
        # Strip trailing "(N rows affected)" lines and sqlcmd noise
        cleaned_lines = []
        for line in stdout.splitlines():
            if line.startswith('(0 rows affected)') or \
               line.startswith('(1 rows affected)') or \
               line.startswith('Changed database context') or \
               line.startswith('Msg '):
                continue
            # Match "(N rows affected)" pattern
            if line.strip().startswith('(') and 'rows affected)' in line:
                continue
            cleaned_lines.append(line)
        
        # Remove trailing empty lines
        while cleaned_lines and cleaned_lines[-1].strip() == '':
            cleaned_lines.pop()
        
        with open(out_csv, 'w') as f:
            f.write('\n'.join(cleaned_lines))
            if cleaned_lines:
                f.write('\n')
        
        # Compute hash
        with open(out_csv, 'rb') as f:
            content = f.read()
        hash_val = hashlib.md5(content).hexdigest()
        
        # Count rows
        row_count = len(cleaned_lines)
        
        status = 'OK' if exit_code == 0 and row_count > 0 else ('NO_RESULTS' if row_count == 0 else 'FAIL')
        summary.append((op_num, status, row_count, hash_val, elapsed, stderr[:200]))
        print(f'  {status}  rows={row_count}  hash={hash_val[:16]}  elapsed={elapsed:.2f}s', flush=True)
        if stderr and exit_code != 0:
            print(f'  STDERR: {stderr[:300]}', flush=True)
    
    # Write summary
    with open(os.path.join(OUT_DIR, 'summary.csv'), 'w') as f:
        f.write('op_id,status,row_count,hash,elapsed_s,stderr\n')
        for op_num, status, rc, h, el, err in summary:
            f.write(f'{op_num},{status},{rc},{h},{el:.2f},"{err}"\n')
    
    # Print summary
    ok = sum(1 for s in summary if s[1] == 'OK')
    print(f'\n=== SUMMARY: {ok}/50 OK ===')

if __name__ == '__main__':
    main()
