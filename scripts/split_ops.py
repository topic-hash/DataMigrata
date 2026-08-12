#!/usr/bin/env python3
"""
Split 02_MSSQL_50_Operations_Expanded.sql into individual op files.
Each op is delimited by "-- OP N:" header and ends at the next "-- OP" header or EOF.
"""
import re
import os
import sys

SQL_FILE = '/home/z/my-project/sql/02_MSSQL_50_Operations_Expanded.sql'
OUT_DIR = '/home/z/my-project/scripts/ops_individual'

OP_HEADER_RE = re.compile(r"^--\s*OP\s+(\d+)\s*:", re.MULTILINE)

def split_ops():
    with open(SQL_FILE, 'r') as f:
        text = f.read()
    matches = list(OP_HEADER_RE.finditer(text))
    if not matches:
        raise RuntimeError("No OP headers found")
    ops = []
    for i, m in enumerate(matches):
        op_num = int(m.group(1))
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        chunk = text[start:end]
        ops.append((op_num, chunk))
    return ops

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    ops = split_ops()
    print(f"Split {len(ops)} operations")
    for op_num, sql in ops:
        path = os.path.join(OUT_DIR, f'op_{op_num:02d}.sql')
        with open(path, 'w') as f:
            f.write(sql)
        print(f"  op_{op_num:02d}.sql ({len(sql)} bytes)")

if __name__ == '__main__':
    main()
