//! Build DuckDB database from exported CSV files with hardcoded table DDL.
//!
//! Direct port of `scripts/build_duckdb.py`.
//!
//! Creates 12 tables with hardcoded DDL and loads CSV data via COPY.

use std::path::Path;

use super::super::common::duckdb_conn::{execute, open_read_write};

/// Table DDL definitions — all 12 tables.
pub fn table_ddl(name: &str) -> Option<&'static str> {
    match name {
        "HR.Employees" => Some(DDL_EMPLOYEES),
        "HR.OrgChart" => Some(DDL_ORGCHART),
        "Sales.Transactions" => Some(DDL_TRANSACTIONS),
        "Sales.TransactionsHistory" => Some(DDL_TRANSACTIONS_HISTORY),
        "Sales.Products" => Some(DDL_PRODUCTS),
        "Sales.CustomerCache" => Some(DDL_CUSTOMER_CACHE),
        "Sales.HighSpeedLookup" => Some(DDL_HIGH_SPEED_LOOKUP),
        "Sales.PartitionedSales" => Some(DDL_PARTITIONED_SALES),
        "Archive.OldTransactions" => Some(DDL_OLD_TRANSACTIONS),
        "Audit.EventLog" => Some(DDL_EVENT_LOG),
        "Security.SensitiveData" => Some(DDL_SENSITIVE_DATA),
        "Staging.ETLSource" => Some(DDL_ETL_SOURCE),
        _ => None,
    }
}

/// File map: table name → CSV filename.
pub fn csv_filename(table: &str) -> Option<&'static str> {
    match table {
        "HR.Employees" => Some("HR_Employees.csv"),
        "HR.OrgChart" => Some("HR_OrgChart.csv"),
        "Sales.Transactions" => Some("Sales_Transactions.csv"),
        "Sales.TransactionsHistory" => Some("Sales_TransactionsHistory.csv"),
        "Sales.Products" => Some("Sales_Products.csv"),
        "Sales.CustomerCache" => Some("Sales_CustomerCache.csv"),
        "Sales.HighSpeedLookup" => Some("Sales_HighSpeedLookup.csv"),
        "Sales.PartitionedSales" => Some("Sales_PartitionedSales.csv"),
        "Archive.OldTransactions" => Some("Archive_OldTransactions.csv"),
        "Audit.EventLog" => Some("Audit_EventLog.csv"),
        "Security.SensitiveData" => Some("Security_SensitiveData.csv"),
        "Staging.ETLSource" => Some("Staging_ETLSource.csv"),
        _ => None,
    }
}

/// All table names in load order.
pub const ALL_TABLES: &[&str] = &[
    "HR.Employees",
    "HR.OrgChart",
    "Sales.Transactions",
    "Sales.TransactionsHistory",
    "Sales.Products",
    "Sales.CustomerCache",
    "Sales.HighSpeedLookup",
    "Sales.PartitionedSales",
    "Archive.OldTransactions",
    "Audit.EventLog",
    "Security.SensitiveData",
    "Staging.ETLSource",
];

/// Build the DuckDB database from CSV files.
///
/// Direct port of the top-level script in `build_duckdb.py`.
pub fn build(db_path: &Path, data_dir: &Path) -> anyhow::Result<()> {
    // Backup if exists
    if db_path.exists() {
        let bak = db_path.with_extension("duckdb.bak");
        let _ = std::fs::copy(db_path, &bak);
    }

    let con = open_read_write(db_path)?;

    // Create schemas
    for schema in &["HR", "Sales", "Archive", "Audit", "Security", "Staging"] {
        let _ = execute(&con, &format!("CREATE SCHEMA IF NOT EXISTS {}", schema));
    }

    // Create tables and load CSV
    for table in ALL_TABLES {
        if let Some(ddl) = table_ddl(table) {
            let _ = execute(&con, &format!("DROP TABLE IF EXISTS {}", table));
            execute(&con, ddl)?;
            if let Some(csv) = csv_filename(table) {
                let csv_path = data_dir.join(csv);
                let copy_sql = format!(
                    "COPY {} FROM '{}' (HEADER false, DELIM ',', QUOTE '\"', ESCAPE '\"', NULL '', FORMAT CSV)",
                    table,
                    csv_path.display()
                );
                if execute(&con, &copy_sql).is_err() {
                    // Fallback with IGNORE_ERRORS
                    let copy_sql = format!(
                        "COPY {} FROM '{}' (HEADER false, DELIM ',', QUOTE '\"', ESCAPE '\"', NULL '', FORMAT CSV, IGNORE_ERRORS 100)",
                        table,
                        csv_path.display()
                    );
                    let _ = execute(&con, &copy_sql);
                }
            }
            let count: i64 = con
                .query_row(&format!("SELECT COUNT(*) FROM {}", table), [], |r| r.get(0))
                .unwrap_or(0);
            eprintln!("  {}: {} rows", table, count);
        }
    }

    Ok(())
}

const DDL_EMPLOYEES: &str = r#"CREATE TABLE HR.Employees (
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
    EmployeeData VARCHAR,
    ProfilePicture BLOB,
    RowVersion BLOB,
    CreatedAt TIMESTAMP,
    ModifiedAt TIMESTAMP
)"#;

const DDL_ORGCHART: &str = r#"CREATE TABLE HR.OrgChart (
    OrgNode VARCHAR,
    OrgLevel INTEGER,
    EmployeeID INTEGER,
    PositionTitle VARCHAR(100),
    Department VARCHAR(50)
)"#;

const DDL_TRANSACTIONS: &str = r#"CREATE TABLE Sales.Transactions (
    TransactionID INTEGER PRIMARY KEY,
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
)"#;

const DDL_TRANSACTIONS_HISTORY: &str = r#"CREATE TABLE Sales.TransactionsHistory (
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
)"#;

const DDL_PRODUCTS: &str = r#"CREATE TABLE Sales.Products (
    ProductID INTEGER PRIMARY KEY,
    ProductName VARCHAR(200),
    Category VARCHAR(50),
    SubCategory VARCHAR(50),
    BasePrice DECIMAL(18,4),
    CostPrice DECIMAL(18,4),
    Specifications VARCHAR,
    SearchVector VARCHAR,
    StockLevel INTEGER,
    ReorderPoint INTEGER,
    IsDiscontinued INTEGER,
    CreatedAt TIMESTAMP
)"#;

const DDL_CUSTOMER_CACHE: &str = r#"CREATE TABLE Sales.CustomerCache (
    CustomerID INTEGER,
    CustomerName VARCHAR(100),
    Email VARCHAR(100),
    RegionCode VARCHAR(20),
    LastOrderDate DATETIME,
    TotalSpent DECIMAL(18,2),
    OrderCount INTEGER
)"#;

const DDL_HIGH_SPEED_LOOKUP: &str = r#"CREATE TABLE Sales.HighSpeedLookup (
    LookupKey INTEGER,
    DataValue VARCHAR(100),
    Category VARCHAR(50),
    Timestamp DATETIME
)"#;

const DDL_PARTITIONED_SALES: &str = r#"CREATE TABLE Sales.PartitionedSales (
    SaleID INTEGER,
    SaleYear INTEGER,
    SaleMonth INTEGER,
    CustomerID INTEGER,
    ProductID INTEGER,
    Amount DECIMAL(18,2),
    Quantity INTEGER
)"#;

const DDL_OLD_TRANSACTIONS: &str = r#"CREATE TABLE Archive.OldTransactions (
    TransactionID INTEGER,
    Year INTEGER,
    Month INTEGER,
    Day INTEGER,
    Amount DECIMAL(18,2),
    CustomerID INTEGER,
    ProductID INTEGER,
    RegionCode VARCHAR(20),
    ArchiveDate DATETIME
)"#;

const DDL_EVENT_LOG: &str = r#"CREATE TABLE Audit.EventLog (
    LogID INTEGER,
    EventTime DATETIME,
    EventType VARCHAR(50),
    TableName VARCHAR(50),
    RecordID INTEGER,
    OldValues VARCHAR,
    NewValues VARCHAR,
    ChangedBy VARCHAR(100),
    SessionContext VARCHAR(100),
    Severity VARCHAR(20)
)"#;

const DDL_SENSITIVE_DATA: &str = r#"CREATE TABLE Security.SensitiveData (
    DataID INTEGER,
    EmployeeID INTEGER,
    SSN VARCHAR(20),
    CreditCard VARCHAR(50),
    BankAccount VARCHAR(50),
    SalaryEncrypted VARCHAR,
    ConfidentialNote VARCHAR,
    EncryptionDate DATETIME
)"#;

const DDL_ETL_SOURCE: &str = r#"CREATE TABLE Staging.ETLSource (
    SourceID INTEGER,
    ExternalProductID VARCHAR(50),
    ProductName VARCHAR(200),
    Category VARCHAR(50),
    Price DECIMAL(18,2),
    ActionCode VARCHAR(10),
    Processed INTEGER,
    ImportedAt DATETIME
)"#;
