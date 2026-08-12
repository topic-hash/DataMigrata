#!/usr/bin/env python3
"""
Build DuckDB database with datetime2 columns as VARCHAR to preserve
the exact 7-digit precision that MSSQL uses.
"""
import duckdb
import os
import json

DB_PATH = '/home/z/my-project/duckdb_migrated/analytics.duckdb'
SCHEMA_JSON = '/home/z/my-project/mssql_data/schema.json'
DATA_DIR = '/home/z/my-project/mssql_data'

if os.path.exists(DB_PATH):
    os.rename(DB_PATH, DB_PATH + '.bak')

con = duckdb.connect(DB_PATH)

with open(SCHEMA_JSON) as f:
    schema = json.load(f)

for s in ['HR', 'Sales', 'Archive', 'Audit', 'Security', 'Staging']:
    con.execute(f"CREATE SCHEMA IF NOT EXISTS {s}")

def fix_type(t, mssql_type):
    """Convert datetime2 to VARCHAR to preserve 7-digit precision."""
    if mssql_type == 'datetime2':
        return 'VARCHAR'
    return t.replace('VARCHAR(-1)', 'VARCHAR')

FILE_MAP = {
    'HR.Employees': 'HR_Employees.csv',
    'HR.OrgChart': 'HR_OrgChart.csv',
    'Sales.Transactions': 'Sales_Transactions.csv',
    'Sales.TransactionsHistory': 'Sales_TransactionsHistory.csv',
    'Sales.Products': 'Sales_Products.csv',
    'Sales.CustomerCache': 'Sales_CustomerCache.csv',
    'Sales.HighSpeedLookup': 'Sales_HighSpeedLookup.csv',
    'Sales.PartitionedSales': 'Sales_PartitionedSales.csv',
    'Archive.OldTransactions': 'Archive_OldTransactions.csv',
    'Audit.EventLog': 'Audit_EventLog.csv',
    'Security.SensitiveData': 'Security_SensitiveData.csv',
    'Staging.ETLSource': 'Staging_ETLSource.csv',
}

for table_name, cols in schema.items():
    col_defs = []
    for col_name, mssql_type, duck_type, nullable in cols:
        duck_type = fix_type(duck_type, mssql_type)
        col_defs.append(f'"{col_name}" {duck_type}')
    ddl = f"CREATE TABLE {table_name} ({', '.join(col_defs)})"
    
    print(f"Creating {table_name}...")
    con.execute(f"DROP TABLE IF EXISTS {table_name}")
    con.execute(ddl)
    
    csv_file = os.path.join(DATA_DIR, FILE_MAP[table_name])
    if not os.path.exists(csv_file):
        continue
    
    try:
        con.execute(f"""
            COPY {table_name} FROM '{csv_file}' (
                HEADER false, DELIM ',', QUOTE '"', ESCAPE '"',
                NULL '', FORMAT CSV, IGNORE_ERRORS 1000
            )
        """)
        count = con.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
        print(f"  Loaded {count} rows")
    except Exception as e:
        print(f"  ERROR: {e}")

# Delete ProductID 1001 (from op 47 MERGE, not in pre-op state)
con.execute("DELETE FROM Sales.Products WHERE ProductID = 1001")
print(f"\nDeleted ProductID 1001. Products count: {con.execute('SELECT COUNT(*) FROM Sales.Products').fetchone()[0]}")

# Verify
print('\n=== TABLE COUNTS ===')
for table_name in schema:
    count = con.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
    print(f'  {table_name}: {count}')

con.close()
print(f'\nDatabase built: {DB_PATH}')
