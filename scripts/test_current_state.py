#!/usr/bin/env python3
"""
Test the current state of all 50 ops against the gold standard.
For each op, run the DuckDB SQL file (if exists) and compare hash.
"""
import duckdb
import os
import hashlib
import csv
import io
import sys
import re

DB_PATH = '/home/z/my-project/duckdb_migrated/analytics.duckdb'
MIGRATED_DIR = '/home/z/my-project/duckdb_migrated'
GOLD_DIR = '/home/z/my-project/gold_standard'

def hash_csv(rows, cols=None):
    """Hash rows in a deterministic way matching the MSSQL gold standard format."""
    if not rows:
        return ''
    # Convert each row to comma-separated string, then hash the full text
    lines = []
    for r in rows:
        # Convert each value to string, handling None
        vals = []
        for v in r:
            if v is None:
                vals.append('')
            elif isinstance(v, float):
                # Match MSSQL formatting: trim trailing zeros
                if v == int(v):
                    vals.append(str(int(v)))
                else:
                    vals.append(str(v))
            elif isinstance(v, bool):
                vals.append('1' if v else '0')
            else:
                vals.append(str(v))
        lines.append(','.join(vals))
    text = '\n'.join(lines)
    return hashlib.md5(text.encode()).hexdigest()

def hash_gold_csv(path):
    """Hash the gold standard CSV file (raw text)."""
    if not os.path.exists(path):
        return None
    with open(path, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()

def run_op(con, sql_text):
    """Run a single SQL op, return (rows, error)."""
    # Split on semicolons but only execute statements that return rows
    # For simplicity, just execute the whole thing as one statement
    # Remove trailing semicolons and GO
    sql_text = re.sub(r'\bGO\b', '', sql_text, flags=re.IGNORECASE)
    sql_text = sql_text.strip().rstrip(';').strip()
    try:
        cur = con.execute(sql_text)
        rows = cur.fetchall()
        return rows, None
    except Exception as e:
        return None, str(e)

def main():
    con = duckdb.connect(DB_PATH, read_only=True)
    
    results = []
    for op_num in range(1, 51):
        op_id = f'op_{op_num:02d}'
        sql_file = os.path.join(MIGRATED_DIR, f'{op_id}.sql')
        gold_file = os.path.join(GOLD_DIR, f'{op_id}.csv')
        
        gold_hash = hash_gold_csv(gold_file)
        gold_rows = 0
        if os.path.exists(gold_file):
            with open(gold_file) as f:
                gold_rows = sum(1 for _ in f)
        
        if not os.path.exists(sql_file):
            results.append((op_num, 'NO_SQL_FILE', 0, gold_rows, '', ''))
            continue
        
        with open(sql_file) as f:
            sql_text = f.read()
        
        rows, err = run_op(con, sql_text)
        if err:
            results.append((op_num, 'EXEC_FAIL', 0, gold_rows, '', err[:120]))
        else:
            duck_hash = hash_csv(rows)
            # Also hash the gold file content the same way (after loading as CSV)
            try:
                gold_data = []
                with open(gold_file, newline='') as f:
                    reader = csv.reader(f)
                    for row in reader:
                        gold_data.append(row)
                # Re-hash gold the same way we hash duckdb rows
                gold_rehash = hash_csv([tuple(r) for r in gold_data])
                status = 'PASS' if duck_hash == gold_rehash else 'MISMATCH'
            except Exception as e:
                status = 'GOLD_ERR'
                gold_rehash = str(e)[:50]
            results.append((op_num, status, len(rows) if rows else 0, gold_rows, duck_hash[:16], err[:120] if err else ''))
    
    # Print results
    pass_count = sum(1 for r in results if r[1] == 'PASS')
    print(f'TOTAL: {pass_count}/50 PASS')
    print()
    print(f'{"OP":>3} {"STATUS":<12} {"ROWS":>6} {"GOLD":>6} {"HASH":<20} ERROR')
    for r in results:
        print(f'{r[0]:>3} {r[1]:<12} {r[2]:>6} {r[3]:>6} {r[4]:<20} {r[5]}')
    
    # Write to file
    with open('/home/z/my-project/scripts/current_state.csv', 'w') as f:
        f.write('op,status,duck_rows,gold_rows,error\n')
        for r in results:
            f.write(f'{r[0]},{r[1]},{r[2]},{r[3]},"{r[5][:200] if r[5] else ""}"\n')

if __name__ == '__main__':
    main()
