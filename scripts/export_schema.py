#!/usr/bin/env python3
"""
Query all column types from MSSQL and generate a DuckDB schema that matches exactly.
This ensures decimal scales, integer types, etc. match MSSQL's output format.
"""
import pyodbc
import json
import os

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

# MSSQL type -> DuckDB type mapping
TYPE_MAP = {
    'int': 'INTEGER',
    'bigint': 'BIGINT',
    'smallint': 'SMALLINT',
    'tinyint': 'UTINYINT',
    'bit': 'INTEGER',
    'decimal': 'DECIMAL({p},{s})',
    'numeric': 'DECIMAL({p},{s})',
    'money': 'DECIMAL(19,4)',
    'smallmoney': 'DECIMAL(10,4)',
    'float': 'DOUBLE',
    'real': 'FLOAT',
    'datetime': 'TIMESTAMP',
    'datetime2': 'TIMESTAMP',
    'smalldatetime': 'TIMESTAMP',
    'date': 'DATE',
    'time': 'TIME',
    'char': 'VARCHAR({p})',
    'varchar': 'VARCHAR({p})',
    'nchar': 'VARCHAR({p})',
    'nvarchar': 'VARCHAR({p})',
    'text': 'VARCHAR',
    'ntext': 'VARCHAR',
    'binary': 'BLOB',
    'varbinary': 'BLOB',
    'image': 'BLOB',
    'uniqueidentifier': 'VARCHAR(36)',
    'xml': 'VARCHAR',
    'geography': 'VARCHAR',
    'geometry': 'VARCHAR',
    'hierarchyid': 'VARCHAR',
    'timestamp': 'BLOB',  # rowversion
}

def get_columns(con, schema, table):
    cursor = con.cursor()
    cursor.execute("""
        SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE,
               CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
    """, (schema, table))
    return cursor.fetchall()

def mssql_to_duckdb(data_type, precision, scale, max_length):
    dt = data_type.lower()
    if dt in TYPE_MAP:
        tmpl = TYPE_MAP[dt]
        if '{p}' in tmpl and '{s}' in tmpl:
            return tmpl.format(p=precision or 18, s=scale or 0)
        elif '{p}' in tmpl:
            return tmpl.format(p=max_length or 255)
        return tmpl
    return 'VARCHAR'  # fallback

def main():
    con = pyodbc.connect(CONN_STR, autocommit=True)
    
    all_schemas = {}
    for schema, table in TABLES:
        cols = get_columns(con, schema, table)
        col_defs = []
        for col_name, data_type, prec, scale, max_len, nullable in cols:
            duck_type = mssql_to_duckdb(data_type, prec, scale, max_len)
            null_str = '' if nullable == 'YES' else ' NOT NULL'
            col_defs.append((col_name, data_type, duck_type, nullable))
        all_schemas[f'{schema}.{table}'] = col_defs
        print(f'{schema}.{table}: {len(col_defs)} columns')
    
    # Save as JSON
    with open('/workspaces/DataMigrata/mssql_data/schema.json', 'w') as f:
        json.dump(all_schemas, f, indent=2)
    
    # Generate DuckDB DDL
    ddl_lines = []
    for full_name, cols in all_schemas.items():
        ddl_lines.append(f'CREATE TABLE {full_name} (')
        col_lines = []
        for col_name, mssql_type, duck_type, nullable in cols:
            col_lines.append(f'    "{col_name}" {duck_type}')
        ddl_lines.append(',\n'.join(col_lines))
        ddl_lines.append(');')
        ddl_lines.append('')
    
    with open('/workspaces/DataMigrata/mssql_data/duckdb_schema.sql', 'w') as f:
        f.write('\n'.join(ddl_lines))
    
    print(f"\nSchema saved to schema.json and duckdb_schema.sql")
    con.close()

if __name__ == '__main__':
    main()
