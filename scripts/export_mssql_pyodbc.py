#!/usr/bin/env python3
"""
Export MSSQL tables to properly-quoted CSV files using pyodbc.
Handles:
- geography/hierarchyid CLR types (cast to text)
- memory-optimized tables (WITH (SNAPSHOT) hint)
- varbinary (hex-encoded)
- xml (as text)
"""
import os
import csv
import pyodbc
import sys
import json

OUT_DIR = '/workspaces/DataMigrata/mssql_data'
os.makedirs(OUT_DIR, exist_ok=True)

CONN_STR = (
    'DRIVER={ODBC Driver 18 for SQL Server};'
    'SERVER=localhost;'
    'PORT=1433;'
    'DATABASE=MSSQL_Advanced_Demo;'
    'UID=sa;'
    'PWD=YourStrong@Passw0rd;'
    'TrustServerCertificate=yes;'
    'Encrypt=no;'
)

# Memory-optimized tables need WITH (SNAPSHOT)
MEMORY_OPTIMIZED = {
    ('Sales', 'CustomerCache'),
    ('Sales', 'HighSpeedLookup'),
}

# Column overrides: for CLR types (geography, hierarchyid), cast to text
# Format: (schema, table) -> {col_name: cast_sql}
COLUMN_CASTS = {
    ('HR', 'OrgChart'): {'OrgNode': 'CAST([OrgNode] AS NVARCHAR(1000))'},
    ('Sales', 'Transactions'): {'Region': 'CAST([Region] AS NVARCHAR(1000))'},
    ('Sales', 'TransactionsHistory'): {'Region': 'CAST([Region] AS NVARCHAR(1000))'},
}

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

def encode_value(v):
    if v is None:
        return ''
    if isinstance(v, bytes):
        return '0x' + v.hex().upper()
    if isinstance(v, bool):
        return '1' if v else '0'
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return str(int(v))
        return str(v)
    if isinstance(v, int):
        return str(v)
    return str(v)

def get_columns(con, schema, name):
    """Get column names from INFORMATION_SCHEMA or sys.columns."""
    cursor = con.cursor()
    cursor.execute(f"""
        SELECT c.name, t.name AS type_name
        FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('[{schema}].[{name}]')
        ORDER BY c.column_id
    """)
    return [(r[0], r[1]) for r in cursor.fetchall()]

def build_select(con, schema, name):
    """Build SELECT statement with proper casts."""
    cols = get_columns(con, schema, name)
    casts = COLUMN_CASTS.get((schema, name), {})
    select_cols = []
    for col_name, col_type in cols:
        if col_name in casts:
            select_cols.append(f'{casts[col_name]} AS [{col_name}]')
        elif col_type in ('geography', 'geometry', 'hierarchyid'):
            select_cols.append(f'CAST([{col_name}] AS NVARCHAR(MAX)) AS [{col_name}]')
        else:
            select_cols.append(f'[{col_name}]')
    
    hint = ' WITH (SNAPSHOT)' if (schema, name) in MEMORY_OPTIMIZED else ''
    sql = f'SELECT {", ".join(select_cols)} FROM [{schema}].[{name}]{hint}'
    return sql, cols

def export_object(con, schema, name):
    out_file = os.path.join(OUT_DIR, f'{schema}_{name}.csv')
    
    # Memory-optimized tables use WITH (SNAPSHOT) hint in SQL, no session-level change needed
    try:
        sql, cols = build_select(con, schema, name)
        cursor = con.cursor()
        cursor.execute(sql)
        col_names = [c[0] for c in cursor.description]
        col_types = [(c[0], str(c[1])) for c in cursor.description]
        
        rows = cursor.fetchall()
        with open(out_file, 'w', newline='') as f:
            w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
            for r in rows:
                w.writerow([encode_value(v) for v in r])
        
        cols_file = os.path.join(OUT_DIR, f'{schema}_{name}_cols.json')
        with open(cols_file, 'w') as f:
            json.dump(col_types, f, indent=2)
        
        print(f'{schema}.{name}: {len(rows)} rows, {len(col_names)} cols -> {out_file}')
    finally:
        pass
    return len(rows)

def main():
    try:
        con = pyodbc.connect(CONN_STR, timeout=60, autocommit=True)
    except Exception as e:
        print(f'Connection failed: {e}')
        sys.exit(1)
    
    print('=== TABLES ===')
    for schema, name in TABLES:
        try:
            export_object(con, schema, name)
        except Exception as e:
            print(f'ERROR exporting {schema}.{name}: {e}')
    
    print('\n=== VIEWS ===')
    for schema, name in VIEWS:
        try:
            export_object(con, schema, name)
        except Exception as e:
            print(f'ERROR exporting {schema}.{name}: {e}')
    
    con.close()

if __name__ == '__main__':
    main()
