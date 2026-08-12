#!/usr/bin/env python3
"""
Export MSSQL data with datetime2 columns CAST to VARCHAR to preserve 7-digit precision.
Also disables RLS to export all rows.
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
    'SERVER=localhost;PORT=1433;DATABASE=MSSQL_Advanced_Demo;'
    'UID=sa;PWD=YourStrong@Passw0rd;'
    'TrustServerCertificate=yes;Encrypt=no;'
)

MEMORY_OPTIMIZED = {
    ('Sales', 'CustomerCache'),
    ('Sales', 'HighSpeedLookup'),
}

# Cast geography, hierarchyid, AND datetime2 to VARCHAR
COLUMN_CASTS = {
    ('HR', 'Employees'): {
        'EmployeeData': 'CAST([EmployeeData] AS NVARCHAR(MAX))',
        'ProfilePicture': 'CONVERT(VARCHAR(MAX), [ProfilePicture], 1)',
        'RowVersion': 'CONVERT(VARCHAR(50), [RowVersion], 1)',
        'CreatedAt': 'CAST([CreatedAt] AS NVARCHAR(50))',
        'ModifiedAt': 'CAST([ModifiedAt] AS NVARCHAR(50))',
    },
    ('HR', 'OrgChart'): {
        'OrgNode': 'CAST([OrgNode] AS NVARCHAR(1000))',
    },
    ('Sales', 'Transactions'): {
        'Region': 'CAST([Region] AS NVARCHAR(1000))',
        'TransactionDate': 'CAST([TransactionDate] AS NVARCHAR(50))',
        'ValidFrom': 'CAST([ValidFrom] AS NVARCHAR(50))',
        'ValidTo': 'CAST([ValidTo] AS NVARCHAR(50))',
    },
    ('Sales', 'TransactionsHistory'): {
        'Region': 'CAST([Region] AS NVARCHAR(1000))',
        'TransactionDate': 'CAST([TransactionDate] AS NVARCHAR(50))',
        'ValidFrom': 'CAST([ValidFrom] AS NVARCHAR(50))',
        'ValidTo': 'CAST([ValidTo] AS NVARCHAR(50))',
    },
    ('Sales', 'Products'): {
        'Specifications': 'CAST([Specifications] AS NVARCHAR(MAX))',
        'SearchVector': 'CAST([SearchVector] AS NVARCHAR(MAX))',
        'CreatedAt': 'CAST([CreatedAt] AS NVARCHAR(50))',
    },
    ('Sales', 'CustomerCache'): {
        'LastOrderDate': 'CAST([LastOrderDate] AS NVARCHAR(50))',
    },
    ('Sales', 'HighSpeedLookup'): {
        'Timestamp': 'CAST([Timestamp] AS NVARCHAR(50))',
    },
    ('Archive', 'OldTransactions'): {
        'ArchiveDate': 'CAST([ArchiveDate] AS NVARCHAR(50))',
    },
    ('Audit', 'EventLog'): {
        'EventTime': 'CAST([EventTime] AS NVARCHAR(50))',
        'OldValues': 'CAST([OldValues] AS NVARCHAR(MAX))',
        'NewValues': 'CAST([NewValues] AS NVARCHAR(MAX))',
        'SessionContext': 'CAST([SessionContext] AS NVARCHAR(MAX))',
    },
    ('Security', 'SensitiveData'): {
        'SSN': 'CONVERT(VARCHAR(MAX), [SSN], 1)',
        'CreditCard': 'CONVERT(VARCHAR(MAX), [CreditCard], 1)',
        'BankAccount': 'CONVERT(VARCHAR(MAX), [BankAccount], 1)',
        'SalaryEncrypted': 'CONVERT(VARCHAR(MAX), [SalaryEncrypted], 1)',
        'ConfidentialNote': 'CAST([ConfidentialNote] AS NVARCHAR(MAX))',
        'EncryptionDate': 'CAST([EncryptionDate] AS NVARCHAR(50))',
    },
    ('Staging', 'ETLSource'): {
        'ImportedAt': 'CAST([ImportedAt] AS NVARCHAR(50))',
    },
}

TABLES = [
    ('HR', 'Employees'), ('HR', 'OrgChart'),
    ('Sales', 'Transactions'), ('Sales', 'TransactionsHistory'),
    ('Sales', 'Products'), ('Sales', 'CustomerCache'),
    ('Sales', 'HighSpeedLookup'), ('Sales', 'PartitionedSales'),
    ('Archive', 'OldTransactions'), ('Audit', 'EventLog'),
    ('Security', 'SensitiveData'), ('Staging', 'ETLSource'),
]

VIEWS = [
    ('Sales', 'vw_ProductSummary'), ('Sales', 'vw_AllTransactions'),
    ('HR', 'vw_ActiveEmployees'), ('Sales', 'vw_TransactionSummary'),
    ('Sales', 'vw_EmployeeQuarterlySales'), ('Sales', 'vw_NormalizedQuarterlySales'),
    ('HR', 'vw_ManagerHierarchy'), ('Sales', 'vw_MultiDimensionalSales'),
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
    return str(v)

def get_columns(con, schema, name):
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
    cols = get_columns(con, schema, name)
    casts = COLUMN_CASTS.get((schema, name), {})
    select_cols = []
    for col_name, col_type in cols:
        if col_name in casts:
            select_cols.append(f'{casts[col_name]} AS [{col_name}]')
        elif col_type in ('geography', 'geometry', 'hierarchyid'):
            select_cols.append(f'CAST([{col_name}] AS NVARCHAR(MAX)) AS [{col_name}]')
        elif col_type == 'datetime2':
            select_cols.append(f'CAST([{col_name}] AS NVARCHAR(50)) AS [{col_name}]')
        else:
            select_cols.append(f'[{col_name}]')
    hint = ' WITH (SNAPSHOT)' if (schema, name) in MEMORY_OPTIMIZED else ''
    return f'SELECT {", ".join(select_cols)} FROM [{schema}].[{name}]{hint}', cols

def export_object(con, schema, name):
    out_file = os.path.join(OUT_DIR, f'{schema}_{name}.csv')
    try:
        sql, cols = build_select(con, schema, name)
        cursor = con.cursor()
        cursor.execute(sql)
        col_names = [c[0] for c in cursor.description]
        rows = cursor.fetchall()
        with open(out_file, 'w', newline='') as f:
            w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
            for r in rows:
                w.writerow([encode_value(v) for v in r])
        print(f'{schema}.{name}: {len(rows)} rows, {len(col_names)} cols')
    except Exception as e:
        print(f'ERROR {schema}.{name}: {e}')

def main():
    con = pyodbc.connect(CONN_STR, timeout=60, autocommit=True)
    # Disable RLS to export all rows
    con.execute('ALTER SECURITY POLICY Security.EmployeeFilterPolicy WITH (STATE=OFF)')
    print('RLS disabled')
    
    print('=== TABLES ===')
    for schema, name in TABLES:
        export_object(con, schema, name)
    print('\n=== VIEWS ===')
    for schema, name in VIEWS:
        export_object(con, schema, name)
    
    # Re-enable RLS
    con.execute('ALTER SECURITY POLICY Security.EmployeeFilterPolicy WITH (STATE=ON)')
    print('\nRLS re-enabled')
    con.close()

if __name__ == '__main__':
    main()
