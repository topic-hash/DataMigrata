#!/usr/bin/env python3
"""
Export all MSSQL tables to CSV files for loading into DuckDB.
Each table is exported with headers, comma-separated, quoted strings.
"""
import os
import subprocess
import sys

OUT_DIR = '/workspaces/DataMigrata/mssql_data'
os.makedirs(OUT_DIR, exist_ok=True)

# Tables to export - mapping (schema, table) -> list of columns to export
# We export ALL columns including LOBs
TABLES = [
    ('HR', 'Employees'),
    ('HR', 'OrgChart'),
    ('Sales', 'Transactions'),
    ('Sales', 'TransactionsHistory'),
    ('Sales', 'Products'),
    ('Sales', 'CustomerCache'),
    ('Sales', 'HighSpeedLookup'),
    ('Sales', 'PartitionedSales'),
    ('Archive', 'OldTransactions'),
    ('Audit', 'EventLog'),
    ('Security', 'SensitiveData'),
    ('Staging', 'ETLSource'),
]

# Also export views that are referenced by ops
VIEWS = [
    ('Sales', 'vw_ProductSummary'),
    ('Sales', 'vw_AllTransactions'),
    ('HR', 'vw_ActiveEmployees'),
    ('Sales', 'vw_TransactionSummary'),
    ('Sales', 'vw_EmployeeQuarterlySales'),
    ('Sales', 'vw_NormalizedQuarterlySales'),
    ('HR', 'vw_ManagerHierarchy'),
    ('Sales', 'vw_MultiDimensionalSales'),
    ('Sales', 'vw_RunningTotalsAndRanks'),
]

def export_table(schema, name):
    out_file = os.path.join(OUT_DIR, f'{schema}_{name}.csv')
    # Use bcp for fast export, or sqlcmd with -o
    # sqlcmd approach:
    cmd = [
        'docker', 'exec', '-i', 'mssql-test',
        '/opt/mssql-tools18/bin/sqlcmd',
        '-S', 'localhost', '-U', 'sa', '-P', 'YourStrong@Passw0rd',
        '-C', '-d', 'MSSQL_Advanced_Demo',
        '-Q', f'SELECT * FROM [{schema}].[{name}]',
        '-W', '-s', ',', '-h', '-1', '-w', '65535',
        '-r', '1',
    ]
    # Add SET options
    set_prefix = "SET QUOTED_IDENTIFIER ON;\nSET ANSI_NULLS ON;\nSET NOCOUNT ON;\nGO\n"
    proc = subprocess.run(cmd, input=set_prefix.encode(), capture_output=True, timeout=300)
    stdout = proc.stdout.decode('utf-8', errors='replace')
    stderr = proc.stderr.decode('utf-8', errors='replace')
    
    # Clean output: remove "(N rows affected)" and empty trailing lines
    cleaned = []
    for line in stdout.splitlines():
        if line.startswith('Changed database context') or line.startswith('Msg ') or line.startswith('DBCC'):
            continue
        if line.strip().startswith('(') and 'rows affected)' in line:
            continue
        cleaned.append(line)
    while cleaned and cleaned[-1].strip() == '':
        cleaned.pop()
    
    with open(out_file, 'w') as f:
        f.write('\n'.join(cleaned))
        if cleaned:
            f.write('\n')
    
    print(f'{schema}.{name}: {len(cleaned)} rows -> {out_file}')
    if stderr:
        print(f'  STDERR: {stderr[:200]}')
    return len(cleaned), stderr

def export_with_columns(schema, name):
    """Export a table and also capture column names."""
    # First get column names
    cmd = [
        'docker', 'exec', '-i', 'mssql-test',
        '/opt/mssql-tools18/bin/sqlcmd',
        '-S', 'localhost', '-U', 'sa', '-P', 'YourStrong@Passw0rd',
        '-C', '-d', 'MSSQL_Advanced_Demo',
        '-Q', f"SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='{schema}' AND TABLE_NAME='{name}' ORDER BY ORDINAL_POSITION",
        '-W', '-s', ',', '-h', '1',
    ]
    proc = subprocess.run(cmd, capture_output=True, timeout=60)
    cols_file = os.path.join(OUT_DIR, f'{schema}_{name}_cols.csv')
    with open(cols_file, 'w') as f:
        f.write(proc.stdout.decode('utf-8', errors='replace'))
    
    # Then export data
    return export_table(schema, name)

def main():
    for schema, name in TABLES:
        try:
            export_with_columns(schema, name)
        except Exception as e:
            print(f'ERROR exporting {schema}.{name}: {e}')
    print('\n=== VIEWS ===')
    for schema, name in VIEWS:
        try:
            export_table(schema, name)
        except Exception as e:
            print(f'ERROR exporting {schema}.{name}: {e}')

if __name__ == '__main__':
    main()
