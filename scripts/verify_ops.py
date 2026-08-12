#!/usr/bin/env python3
"""
Verify DuckDB SQL ops against MSSQL gold standard CSVs.
Uses DuckDB's COPY to export query results to CSV, then compares byte-by-byte
after normalizing formatting (decimal places, NULL handling, etc.).
"""
import duckdb
import os
import sys
import csv
import io
import hashlib
import re

DB_PATH = '/home/z/my-project/duckdb_migrated/analytics.duckdb'
SQL_DIR = '/home/z/my-project/duckdb_migrated'
GOLD_DIR = '/home/z/my-project/gold_standard'

def normalize_value(v):
    """Convert a Python value to the string format MSSQL sqlcmd produces."""
    if v is None:
        return 'NULL'
    if isinstance(v, bytes):
        return '0x' + v.hex().upper()
    if isinstance(v, bool):
        return '1' if v else '0'
    import datetime
    if isinstance(v, datetime.datetime):
        s = v.strftime('%Y-%m-%d %H:%M:%S.%f')
        return s + '0'
    if isinstance(v, datetime.date):
        return v.strftime('%Y-%m-%d')
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return str(int(v))
        return str(v)
    # Decimal, int, str
    return str(v)

def row_to_csv_line(row):
    """Convert a row tuple to a CSV line matching MSSQL sqlcmd format.
    sqlcmd -s, does NOT quote fields — just joins with commas."""
    vals = [normalize_value(v) for v in row]
    return ','.join(vals)

def run_op(con, sql_text):
    """Execute SQL and return (rows, error)."""
    # Remove trailing semicolon and GO
    sql_text = re.sub(r'\bGO\b', '', sql_text, flags=re.IGNORECASE)
    # If multiple statements separated by ;, only run the last SELECT
    # Actually, just try the whole thing first
    sql_text = sql_text.strip().rstrip(';').strip()
    try:
        cur = con.execute(sql_text)
        if cur is None:
            return [], None
        rows = cur.fetchall()
        return rows, None
    except Exception as e:
        return None, str(e)

def hash_text(text):
    return hashlib.md5(text.encode()).hexdigest()

def compare_op(con, op_num):
    """Compare DuckDB output to gold standard for op_num."""
    op_id = f'op_{op_num:02d}'
    sql_file = os.path.join(SQL_DIR, f'{op_id}.sql')
    gold_file = os.path.join(GOLD_DIR, f'{op_id}.csv')
    
    if not os.path.exists(sql_file):
        return {'op': op_num, 'status': 'NO_SQL', 'duck_rows': 0, 'gold_rows': 0, 'error': 'no sql file'}
    
    if not os.path.exists(gold_file):
        return {'op': op_num, 'status': 'NO_GOLD', 'duck_rows': 0, 'gold_rows': 0, 'error': 'no gold file'}
    
    with open(sql_file) as f:
        sql_text = f.read()
    
    # Read gold standard
    with open(gold_file) as f:
        gold_content = f.read()
    gold_lines = gold_content.splitlines()
    gold_rows = len(gold_lines)
    gold_hash = hash_text(gold_content.rstrip('\n'))
    
    # Run DuckDB
    rows, err = run_op(con, sql_text)
    if err:
        return {'op': op_num, 'status': 'EXEC_FAIL', 'duck_rows': 0, 'gold_rows': gold_rows, 
                'gold_hash': gold_hash[:16], 'error': err[:200]}
    
    duck_rows = len(rows) if rows else 0
    # Format DuckDB output as CSV
    if rows:
        duck_lines = [row_to_csv_line(r) for r in rows]
        duck_content = '\n'.join(duck_lines)
    else:
        duck_content = ''
    duck_hash = hash_text(duck_content.rstrip('\n'))
    
    if duck_hash == gold_hash:
        return {'op': op_num, 'status': 'PASS', 'duck_rows': duck_rows, 'gold_rows': gold_rows,
                'gold_hash': gold_hash[:16], 'duck_hash': duck_hash[:16], 'error': ''}
    
    # Mismatch - find first differing line for debugging
    duck_lines_norm = duck_content.splitlines() if duck_content else []
    first_diff = -1
    for i in range(min(len(duck_lines_norm), len(gold_lines))):
        if duck_lines_norm[i] != gold_lines[i]:
            first_diff = i
            break
    if first_diff == -1 and len(duck_lines_norm) != len(gold_lines):
        first_diff = min(len(duck_lines_norm), len(gold_lines))
    
    diff_info = ''
    if first_diff < len(duck_lines_norm) and first_diff < len(gold_lines):
        diff_info = f'line {first_diff}: duck={duck_lines_norm[first_diff][:80]} | gold={gold_lines[first_diff][:80]}'
    elif first_diff < len(gold_lines):
        diff_info = f'line {first_diff}: duck=<missing> | gold={gold_lines[first_diff][:80]}'
    elif first_diff < len(duck_lines_norm):
        diff_info = f'line {first_diff}: duck={duck_lines_norm[first_diff][:80]} | gold=<missing>'
    
    return {'op': op_num, 'status': 'MISMATCH', 'duck_rows': duck_rows, 'gold_rows': gold_rows,
            'gold_hash': gold_hash[:16], 'duck_hash': duck_hash[:16], 'error': diff_info[:200]}

def main():
    con = duckdb.connect(DB_PATH, read_only=True)
    # Load spatial extension for spatial ops
    try:
        con.execute("LOAD spatial")
    except:
        pass
    
    results = []
    for op_num in range(1, 51):
        r = compare_op(con, op_num)
        results.append(r)
        status = r['status']
        if status == 'PASS':
            print(f'  OP {op_num:02d}: PASS  ({r["duck_rows"]} rows)')
        elif status == 'MISMATCH':
            print(f'  OP {op_num:02d}: MISMATCH  duck={r["duck_rows"]} gold={r["gold_rows"]}  {r["error"][:100]}')
        else:
            print(f'  OP {op_num:02d}: {status}  {r.get("error", "")[:100]}')
    
    pass_count = sum(1 for r in results if r['status'] == 'PASS')
    print(f'\n=== TOTAL: {pass_count}/50 PASS ===')
    
    # Write CSV
    with open('/home/z/my-project/scripts/verification_results.csv', 'w') as f:
        f.write('op,status,duck_rows,gold_rows,gold_hash,duck_hash,error\n')
        for r in results:
            f.write(f'{r["op"]},{r["status"]},{r["duck_rows"]},{r["gold_rows"]},'
                    f'{r.get("gold_hash","")},{r.get("duck_hash","")},"{r["error"][:200]}"\n')
    
    con.close()

if __name__ == '__main__':
    main()
