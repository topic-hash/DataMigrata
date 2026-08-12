#!/usr/bin/env python3
"""
Build a fresh DuckDB database from the exported MSSQL CSV files.
Creates schema with proper types, loads data, creates views.
"""
import duckdb
import os
import json
import sys

DB_PATH = '/home/z/my-project/duckdb_migrated/analytics.duckdb'
DATA_DIR = '/home/z/my-project/mssql_data'

# Backup the old database
if os.path.exists(DB_PATH):
    os.rename(DB_PATH, DB_PATH + '.bak')

con = duckdb.connect(DB_PATH)

# Create schemas
con.execute("CREATE SCHEMA IF NOT EXISTS HR")
con.execute("CREATE SCHEMA IF NOT EXISTS Sales")
con.execute("CREATE SCHEMA IF NOT EXISTS Archive")
con.execute("CREATE SCHEMA IF NOT EXISTS Audit")
con.execute("CREATE SCHEMA IF NOT EXISTS Security")
con.execute("CREATE SCHEMA IF NOT EXISTS Staging")

# Table definitions with explicit types matching MSSQL
TABLES = {
    'HR.Employees': '''
        CREATE TABLE HR.Employees (
            EmployeeID INTEGER PRIMARY KEY,
            ManagerID INTEGER,
            FullName VARCHAR(100),
            Email VARCHAR(100),
            Department VARCHAR(50),
            JobTitle VARCHAR(100),
            Salary DECIMAL(18,2),
            HireDate DATE,
            TerminationDate DATE,
            IsActive INTEGER,
            SecurityClearanceLevel INTEGER,
            EmployeeData VARCHAR,  -- XML stored as text
            ProfilePicture BLOB,
            RowVersion BLOB,
            CreatedAt TIMESTAMP,
            ModifiedAt TIMESTAMP
        )
    ''',
    'HR.OrgChart': '''
        CREATE TABLE HR.OrgChart (
            OrgNode VARCHAR,  -- HIERARCHYID stored as string path
            OrgLevel INTEGER,
            EmployeeID INTEGER,
            PositionTitle VARCHAR(100),
            Department VARCHAR(50)
        )
    ''',
    'Sales.Transactions': '''
        CREATE TABLE Sales.Transactions (
            TransactionID INTEGER PRIMARY KEY,
            EmployeeID INTEGER,
            CustomerID INTEGER,
            ProductID INTEGER,
            Quantity INTEGER,
            UnitPrice DECIMAL(18,4),
            DiscountPct DECIMAL(5,4),
            TotalAmount DECIMAL(18,2),
            TransactionDate TIMESTAMP,
            Region VARCHAR,  -- geography stored as text
            TransactionDetails VARCHAR,  -- JSON stored as text
            PaymentStatus VARCHAR(20),
            ValidFrom TIMESTAMP,
            ValidTo TIMESTAMP
        )
    ''',
    'Sales.TransactionsHistory': '''
        CREATE TABLE Sales.TransactionsHistory (
            TransactionID INTEGER,
            EmployeeID INTEGER,
            CustomerID INTEGER,
            ProductID INTEGER,
            Quantity INTEGER,
            UnitPrice DECIMAL(18,4),
            DiscountPct DECIMAL(5,4),
            TotalAmount DECIMAL(18,2),
            TransactionDate TIMESTAMP,
            Region VARCHAR,
            TransactionDetails VARCHAR,
            PaymentStatus VARCHAR(20),
            ValidFrom TIMESTAMP,
            ValidTo TIMESTAMP
        )
    ''',
    'Sales.Products': '''
        CREATE TABLE Sales.Products (
            ProductID INTEGER PRIMARY KEY,
            ProductName VARCHAR(200),
            Category VARCHAR(50),
            SubCategory VARCHAR(50),
            BasePrice DECIMAL(18,4),
            CostPrice DECIMAL(18,4),
            Specifications VARCHAR,  -- text with commas
            SearchVector VARCHAR,  -- computed column
            StockLevel INTEGER,
            ReorderPoint INTEGER,
            IsDiscontinued INTEGER,
            CreatedAt TIMESTAMP
        )
    ''',
    'Sales.CustomerCache': '''
        CREATE TABLE Sales.CustomerCache (
            CustomerID INTEGER,
            CustomerName VARCHAR(100),
            Email VARCHAR(100),
            RegionCode VARCHAR(20),
            LastOrderDate DATETIME,
            TotalSpent DECIMAL(18,2),
            OrderCount INTEGER
        )
    ''',
    'Sales.HighSpeedLookup': '''
        CREATE TABLE Sales.HighSpeedLookup (
            LookupKey INTEGER,
            DataValue VARCHAR(100),
            Category VARCHAR(50),
            Timestamp DATETIME
        )
    ''',
    'Sales.PartitionedSales': '''
        CREATE TABLE Sales.PartitionedSales (
            SaleID INTEGER,
            SaleYear INTEGER,
            SaleMonth INTEGER,
            CustomerID INTEGER,
            ProductID INTEGER,
            Amount DECIMAL(18,2),
            Quantity INTEGER
        )
    ''',
    'Archive.OldTransactions': '''
        CREATE TABLE Archive.OldTransactions (
            TransactionID INTEGER,
            Year INTEGER,
            Month INTEGER,
            Day INTEGER,
            Amount DECIMAL(18,2),
            CustomerID INTEGER,
            ProductID INTEGER,
            RegionCode VARCHAR(20),
            ArchiveDate DATETIME
        )
    ''',
    'Audit.EventLog': '''
        CREATE TABLE Audit.EventLog (
            LogID INTEGER,
            EventTime DATETIME,
            EventType VARCHAR(50),
            TableName VARCHAR(50),
            RecordID INTEGER,
            OldValues VARCHAR,  -- JSON
            NewValues VARCHAR,  -- JSON
            ChangedBy VARCHAR(100),
            SessionContext VARCHAR(100),
            Severity VARCHAR(20)
        )
    ''',
    'Security.SensitiveData': '''
        CREATE TABLE Security.SensitiveData (
            DataID INTEGER,
            EmployeeID INTEGER,
            SSN VARCHAR(20),
            CreditCard VARCHAR(50),
            BankAccount VARCHAR(50),
            SalaryEncrypted VARCHAR,  -- varbinary as hex string
            ConfidentialNote VARCHAR,
            EncryptionDate DATETIME
        )
    ''',
    'Staging.ETLSource': '''
        CREATE TABLE Staging.ETLSource (
            SourceID INTEGER,
            ExternalProductID VARCHAR(50),
            ProductName VARCHAR(200),
            Category VARCHAR(50),
            Price DECIMAL(18,2),
            ActionCode VARCHAR(10),
            Processed INTEGER,
            ImportedAt DATETIME
        )
    ''',
}

# File mapping: (schema_table) -> filename
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

# Create and load each table
for table_name, ddl in TABLES.items():
    print(f'Creating {table_name}...')
    try:
        con.execute(f"DROP TABLE IF EXISTS {table_name}")
        con.execute(ddl)
    except Exception as e:
        print(f'  ERROR creating: {e}')
        continue
    
    csv_file = os.path.join(DATA_DIR, FILE_MAP[table_name])
    if not os.path.exists(csv_file):
        print(f'  CSV not found: {csv_file}')
        continue
    
    try:
        # Use DuckDB's COPY to load CSV
        # Handle NULL values, empty strings
        con.execute(f"""
            COPY {table_name} FROM '{csv_file}' (
                HEADER false,
                DELIM ',',
                QUOTE '"',
                ESCAPE '"',
                NULL '',
                FORMAT CSV
            )
        """)
        count = con.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
        print(f'  Loaded {count} rows')
    except Exception as e:
        print(f'  ERROR loading: {e}')
        # Try loading with more lenient options
        try:
            con.execute(f"""
                COPY {table_name} FROM '{csv_file}' (
                    HEADER false,
                    DELIM ',',
                    QUOTE '"',
                    ESCAPE '"',
                    NULL '',
                    FORMAT CSV,
                    IGNORE_ERRORS 100
                )
            """)
            count = con.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
            print(f'  Loaded {count} rows (with errors)')
        except Exception as e2:
            print(f'  ERROR loading (lenient): {e2}')

# Verify counts
print('\n=== TABLE COUNTS ===')
for table_name in TABLES:
    try:
        count = con.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
        print(f'  {table_name}: {count}')
    except Exception as e:
        print(f'  {table_name}: ERROR {e}')

con.close()
print(f'\nDatabase built: {DB_PATH}')
