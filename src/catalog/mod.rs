//! Catalog abstraction — maps logical MSSQL schema to physical DuckDB schema.

use std::collections::HashMap;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CatalogError {
    #[error("table not found in catalog: {0}")]
    TableNotFound(String),
    #[error("column not found: {0}.{1}")]
    ColumnNotFound(String, String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SchemaVariant {
    Baseline,
    ColumnarOptimized,
    PreComputed,
}

impl SchemaVariant {
    pub fn name(&self) -> &'static str {
        match self { Self::Baseline => "baseline", Self::ColumnarOptimized => "columnar_optimized", Self::PreComputed => "pre_computed" }
    }
    pub fn all() -> &'static [SchemaVariant] { &[Self::Baseline, Self::ColumnarOptimized, Self::PreComputed] }
}

impl std::fmt::Display for SchemaVariant {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, "{}", self.name()) }
}

#[derive(Debug, Clone)]
pub struct LogicalColumn {
    pub name: String,
    pub data_type: LogicalType,
    pub nullable: bool,
    pub is_computed: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LogicalType {
    Integer, BigInt, Decimal(u8, u8), Varchar(Option<u32>), NVarchar(Option<u32>),
    Text, Date, Timestamp, Boolean, Binary, Xml, Json, Geography, HierarchyId, UniqueIdentifier,
}

impl std::fmt::Display for LogicalType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Integer => write!(f, "INTEGER"),
            Self::BigInt => write!(f, "BIGINT"),
            Self::Decimal(p, s) => write!(f, "DECIMAL({}, {})", p, s),
            Self::Varchar(n) => write!(f, "VARCHAR({})", n.unwrap_or(0)),
            Self::NVarchar(n) => write!(f, "VARCHAR({})", n.unwrap_or(0)),
            Self::Text => write!(f, "TEXT"),
            Self::Date => write!(f, "DATE"),
            Self::Timestamp => write!(f, "TIMESTAMP"),
            Self::Boolean => write!(f, "BOOLEAN"),
            Self::Binary => write!(f, "BLOB"),
            Self::Xml => write!(f, "TEXT"),
            Self::Json => write!(f, "JSON"),
            Self::Geography => write!(f, "TEXT"),
            Self::HierarchyId => write!(f, "TEXT"),
            Self::UniqueIdentifier => write!(f, "TEXT"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct LogicalTable {
    pub schema: String,
    pub name: String,
    pub columns: Vec<LogicalColumn>,
    pub primary_key: Vec<String>,
}

impl LogicalTable {
    pub fn full_name(&self) -> String { format!("{}.{}", self.schema, self.name) }
}

#[derive(Debug, Clone)]
pub struct PhysicalColumn {
    pub logical_name: String,
    pub physical_name: String,
    pub duckdb_type: String,
    pub is_auxiliary: bool,
}

#[derive(Debug, Clone)]
pub struct PhysicalTable {
    pub duckdb_table_name: String,
    pub columns: Vec<PhysicalColumn>,
    pub create_sql: String,
}

#[derive(Debug, Clone)]
pub struct CatalogEntry {
    pub logical_table: LogicalTable,
    pub physical_table: PhysicalTable,
    pub variant: SchemaVariant,
}

#[derive(Debug, Clone)]
pub struct Catalog {
    entries: HashMap<String, CatalogEntry>,
    active_variant: SchemaVariant,
}

impl Catalog {
    pub fn new(variant: SchemaVariant) -> Self {
        Self { entries: HashMap::new(), active_variant: variant }
    }

    pub fn default_mssql_catalog(variant: SchemaVariant) -> Self {
        let mut cat = Self::new(variant);
        cat.register(LogicalTable {
            schema: "HR".into(), name: "Employees".into(),
            columns: vec![
                LogicalColumn { name: "EmployeeID".into(), data_type: LogicalType::Integer, nullable: false, is_computed: false },
                LogicalColumn { name: "ManagerID".into(), data_type: LogicalType::Integer, nullable: true, is_computed: false },
                LogicalColumn { name: "FullName".into(), data_type: LogicalType::NVarchar(Some(200)), nullable: false, is_computed: false },
                LogicalColumn { name: "Email".into(), data_type: LogicalType::NVarchar(Some(200)), nullable: true, is_computed: false },
                LogicalColumn { name: "Department".into(), data_type: LogicalType::NVarchar(Some(100)), nullable: true, is_computed: false },
                LogicalColumn { name: "JobTitle".into(), data_type: LogicalType::NVarchar(Some(200)), nullable: true, is_computed: false },
                LogicalColumn { name: "Salary".into(), data_type: LogicalType::Decimal(18, 2), nullable: true, is_computed: false },
                LogicalColumn { name: "HireDate".into(), data_type: LogicalType::Date, nullable: true, is_computed: false },
                LogicalColumn { name: "TerminationDate".into(), data_type: LogicalType::Date, nullable: true, is_computed: false },
                LogicalColumn { name: "IsActive".into(), data_type: LogicalType::Boolean, nullable: false, is_computed: true },
                LogicalColumn { name: "EmployeeData".into(), data_type: LogicalType::Xml, nullable: true, is_computed: false },
                LogicalColumn { name: "RowVersion".into(), data_type: LogicalType::Binary, nullable: false, is_computed: false },
            ],
            primary_key: vec!["EmployeeID".into()],
        });
        cat.register(LogicalTable {
            schema: "HR".into(), name: "OrgChart".into(),
            columns: vec![
                LogicalColumn { name: "OrgNode".into(), data_type: LogicalType::HierarchyId, nullable: false, is_computed: false },
                LogicalColumn { name: "OrgLevel".into(), data_type: LogicalType::Integer, nullable: true, is_computed: true },
                LogicalColumn { name: "EmployeeID".into(), data_type: LogicalType::Integer, nullable: true, is_computed: false },
                LogicalColumn { name: "PositionTitle".into(), data_type: LogicalType::NVarchar(Some(200)), nullable: true, is_computed: false },
                LogicalColumn { name: "Department".into(), data_type: LogicalType::NVarchar(Some(100)), nullable: true, is_computed: false },
            ],
            primary_key: vec!["OrgNode".into()],
        });
        cat.register(LogicalTable {
            schema: "Sales".into(), name: "Transactions".into(),
            columns: vec![
                LogicalColumn { name: "TransactionID".into(), data_type: LogicalType::BigInt, nullable: false, is_computed: false },
                LogicalColumn { name: "EmployeeID".into(), data_type: LogicalType::Integer, nullable: true, is_computed: false },
                LogicalColumn { name: "CustomerID".into(), data_type: LogicalType::Integer, nullable: false, is_computed: false },
                LogicalColumn { name: "ProductID".into(), data_type: LogicalType::Integer, nullable: true, is_computed: false },
                LogicalColumn { name: "Quantity".into(), data_type: LogicalType::Integer, nullable: false, is_computed: false },
                LogicalColumn { name: "UnitPrice".into(), data_type: LogicalType::Decimal(18, 4), nullable: false, is_computed: false },
                LogicalColumn { name: "DiscountPct".into(), data_type: LogicalType::Decimal(5, 4), nullable: true, is_computed: false },
                LogicalColumn { name: "TotalAmount".into(), data_type: LogicalType::Decimal(17, 2), nullable: true, is_computed: true },
                LogicalColumn { name: "TransactionDate".into(), data_type: LogicalType::Timestamp, nullable: true, is_computed: false },
                LogicalColumn { name: "Region".into(), data_type: LogicalType::Geography, nullable: true, is_computed: false },
                LogicalColumn { name: "TransactionDetails".into(), data_type: LogicalType::Json, nullable: true, is_computed: false },
                LogicalColumn { name: "PaymentStatus".into(), data_type: LogicalType::NVarchar(Some(40)), nullable: true, is_computed: false },
                LogicalColumn { name: "ValidFrom".into(), data_type: LogicalType::Timestamp, nullable: false, is_computed: false },
                LogicalColumn { name: "ValidTo".into(), data_type: LogicalType::Timestamp, nullable: false, is_computed: false },
            ],
            primary_key: vec!["TransactionID".into()],
        });
        cat.register(LogicalTable {
            schema: "Sales".into(), name: "Products".into(),
            columns: vec![
                LogicalColumn { name: "ProductID".into(), data_type: LogicalType::Integer, nullable: false, is_computed: false },
                LogicalColumn { name: "ProductName".into(), data_type: LogicalType::NVarchar(Some(400)), nullable: false, is_computed: false },
                LogicalColumn { name: "Category".into(), data_type: LogicalType::NVarchar(Some(100)), nullable: true, is_computed: false },
                LogicalColumn { name: "BasePrice".into(), data_type: LogicalType::Decimal(18, 4), nullable: true, is_computed: false },
                LogicalColumn { name: "CostPrice".into(), data_type: LogicalType::Decimal(18, 4), nullable: true, is_computed: false },
                LogicalColumn { name: "StockLevel".into(), data_type: LogicalType::Integer, nullable: true, is_computed: false },
                LogicalColumn { name: "IsDiscontinued".into(), data_type: LogicalType::Boolean, nullable: true, is_computed: false },
            ],
            primary_key: vec!["ProductID".into()],
        });
        cat
    }

    pub fn register(&mut self, logical: LogicalTable) {
        let physical = self.generate_physical(&logical);
        let key = logical.full_name();
        self.entries.insert(key, CatalogEntry { logical_table: logical, physical_table: physical, variant: self.active_variant });
    }

    fn generate_physical(&self, logical: &LogicalTable) -> PhysicalTable {
        match self.active_variant {
            SchemaVariant::Baseline => self.generate_baseline(logical),
            SchemaVariant::ColumnarOptimized => self.generate_columnar(logical),
            SchemaVariant::PreComputed => self.generate_precomputed(logical),
        }
    }

    fn generate_baseline(&self, logical: &LogicalTable) -> PhysicalTable {
        let table_name = format!("{}_{}", logical.schema.to_lowercase(), logical.name.to_lowercase());
        let mut columns = Vec::new();
        let mut col_defs = Vec::new();
        for col in &logical.columns {
            let duckdb_type = self.type_to_duckdb(&col.data_type);
            columns.push(PhysicalColumn { logical_name: col.name.clone(), physical_name: col.name.clone(), duckdb_type: duckdb_type.clone(), is_auxiliary: false });
            col_defs.push(format!("  \"{}\" {}", col.name, duckdb_type));
        }
        let pk_cols = logical.primary_key.join(", ");
        col_defs.push(format!("  PRIMARY KEY ({})", pk_cols));
        let create_sql = format!("CREATE TABLE IF NOT EXISTS {} (\n{}\n);", table_name, col_defs.join(",\n"));
        PhysicalTable { duckdb_table_name: table_name, columns, create_sql }
    }

    fn generate_columnar(&self, logical: &LogicalTable) -> PhysicalTable {
        let table_name = format!("{}_{}", logical.schema.to_lowercase(), logical.name.to_lowercase());
        let lob_table_name = format!("{}_lob", table_name);
        let mut columns = Vec::new();
        let mut col_defs = Vec::new();
        let mut lob_columns = Vec::new();
        for col in &logical.columns {
            match col.data_type {
                LogicalType::Xml | LogicalType::Json | LogicalType::Binary | LogicalType::Geography => {
                    columns.push(PhysicalColumn { logical_name: col.name.clone(), physical_name: format!("{}_id", col.name.to_lowercase()), duckdb_type: "INTEGER".into(), is_auxiliary: true });
                    col_defs.push(format!("  \"{}_id\" INTEGER", col.name));
                    lob_columns.push((col.name.clone(), self.type_to_duckdb(&col.data_type)));
                }
                LogicalType::NVarchar(Some(n)) if n > 100 => {
                    columns.push(PhysicalColumn { logical_name: col.name.clone(), physical_name: col.name.clone(), duckdb_type: "TEXT".into(), is_auxiliary: false });
                    col_defs.push(format!("  \"{}\" TEXT", col.name));
                }
                _ => {
                    let duckdb_type = self.type_to_duckdb(&col.data_type);
                    columns.push(PhysicalColumn { logical_name: col.name.clone(), physical_name: col.name.clone(), duckdb_type: duckdb_type.clone(), is_auxiliary: false });
                    col_defs.push(format!("  \"{}\" {}", col.name, duckdb_type));
                }
            }
        }
        let pk_cols = logical.primary_key.join(", ");
        col_defs.push(format!("  PRIMARY KEY ({})", pk_cols));
        let mut create_sql = format!("CREATE TABLE IF NOT EXISTS {} (\n{}\n);", table_name, col_defs.join(",\n"));
        if !lob_columns.is_empty() {
            let lob_col_defs: Vec<String> = lob_columns.iter().map(|(name, dtype)| format!("  \"{}\" {}", name, dtype)).collect();
            create_sql.push_str(&format!("\nCREATE TABLE IF NOT EXISTS {} (\n  \"row_id\" INTEGER PRIMARY KEY,\n{}\n);", lob_table_name, lob_col_defs.join(",\n")));
        }
        PhysicalTable { duckdb_table_name: table_name, columns, create_sql }
    }

    fn generate_precomputed(&self, logical: &LogicalTable) -> PhysicalTable {
        let table_name = format!("{}_{}", logical.schema.to_lowercase(), logical.name.to_lowercase());
        let mut columns = Vec::new();
        let mut col_defs = Vec::new();
        for col in &logical.columns {
            let duckdb_type = self.type_to_duckdb(&col.data_type);
            columns.push(PhysicalColumn { logical_name: col.name.clone(), physical_name: col.name.clone(), duckdb_type: duckdb_type.clone(), is_auxiliary: false });
            col_defs.push(format!("  \"{}\" {}", col.name, duckdb_type));
        }
        if logical.name == "Employees" {
            columns.push(PhysicalColumn { logical_name: "_materialized_path".into(), physical_name: "materialized_path".into(), duckdb_type: "TEXT".into(), is_auxiliary: true });
            col_defs.push("  \"materialized_path\" TEXT".to_string());
            columns.push(PhysicalColumn { logical_name: "_depth".into(), physical_name: "depth".into(), duckdb_type: "INTEGER".into(), is_auxiliary: true });
            col_defs.push("  \"depth\" INTEGER".to_string());
        }
        if logical.name == "Transactions" && logical.columns.iter().any(|c| c.name == "Region") {
            columns.push(PhysicalColumn { logical_name: "_bbox_lat".into(), physical_name: "bbox_lat".into(), duckdb_type: "DOUBLE".into(), is_auxiliary: true });
            col_defs.push("  \"bbox_lat\" DOUBLE".to_string());
            columns.push(PhysicalColumn { logical_name: "_bbox_lon".into(), physical_name: "bbox_lon".into(), duckdb_type: "DOUBLE".into(), is_auxiliary: true });
            col_defs.push("  \"bbox_lon\" DOUBLE".to_string());
        }
        let pk_cols = logical.primary_key.join(", ");
        col_defs.push(format!("  PRIMARY KEY ({})", pk_cols));
        let create_sql = format!("CREATE TABLE IF NOT EXISTS {} (\n{}\n);", table_name, col_defs.join(",\n"));
        PhysicalTable { duckdb_table_name: table_name, columns, create_sql }
    }

    fn type_to_duckdb(&self, lt: &LogicalType) -> String {
        match lt {
            LogicalType::Integer => "INTEGER".into(),
            LogicalType::BigInt => "BIGINT".into(),
            LogicalType::Decimal(p, s) => format!("DECIMAL({}, {})", p, s),
            LogicalType::Varchar(n) | LogicalType::NVarchar(n) => match n { Some(0) | None => "TEXT".into(), Some(len) => format!("VARCHAR({})", len) },
            LogicalType::Text => "TEXT".into(),
            LogicalType::Date => "DATE".into(),
            LogicalType::Timestamp => "TIMESTAMP".into(),
            LogicalType::Boolean => "BOOLEAN".into(),
            LogicalType::Binary => "BLOB".into(),
            LogicalType::Xml => "TEXT".into(),
            LogicalType::Json => "JSON".into(),
            LogicalType::Geography => "TEXT".into(),
            LogicalType::HierarchyId => "TEXT".into(),
            LogicalType::UniqueIdentifier => "TEXT".into(),
        }
    }

    pub fn lookup(&self, logical_name: &str) -> Result<&CatalogEntry, CatalogError> {
        self.entries.get(logical_name)
            .or_else(|| self.entries.iter().find(|(k, _)| k.eq_ignore_ascii_case(logical_name)).map(|(_, v)| v))
            .ok_or_else(|| CatalogError::TableNotFound(logical_name.to_string()))
    }

    pub fn physical_table_name(&self, logical_name: &str) -> Result<&str, CatalogError> {
        Ok(&self.lookup(logical_name)?.physical_table.duckdb_table_name)
    }

    pub fn physical_column_name(&self, table: &str, column: &str) -> Result<&str, CatalogError> {
        let entry = self.lookup(table)?;
        entry.physical_table.columns.iter()
            .find(|c| c.logical_name.eq_ignore_ascii_case(column))
            .map(|c| c.physical_name.as_str())
            .ok_or_else(|| CatalogError::ColumnNotFound(table.to_string(), column.to_string()))
    }

    pub fn ddl(&self) -> String {
        self.entries.values().map(|e| e.physical_table.create_sql.clone()).collect::<Vec<_>>().join("\n\n")
    }

    pub fn variant(&self) -> SchemaVariant { self.active_variant }

    pub fn switch_variant(&mut self, variant: SchemaVariant) {
        self.active_variant = variant;
        let logical_tables: Vec<LogicalTable> = self.entries.values().map(|e| e.logical_table.clone()).collect();
        self.entries.clear();
        for logical in logical_tables { self.register(logical); }
    }

    pub fn tables(&self) -> Vec<&CatalogEntry> { self.entries.values().collect() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_catalog_baseline() {
        let cat = Catalog::default_mssql_catalog(SchemaVariant::Baseline);
        let entry = cat.lookup("HR.Employees").unwrap();
        assert_eq!(entry.logical_table.columns.len(), 12);
        assert_eq!(entry.physical_table.duckdb_table_name, "hr_employees");
    }

    #[test]
    fn test_columnar_variant_has_lob_side_table() {
        let cat = Catalog::default_mssql_catalog(SchemaVariant::ColumnarOptimized);
        let entry = cat.lookup("HR.Employees").unwrap();
        assert!(entry.physical_table.create_sql.contains("hr_employees_lob"));
        assert!(entry.physical_table.columns.iter().any(|c| c.physical_name == "employeedata_id"));
    }

    #[test]
    fn test_precomputed_variant_has_materialized_path() {
        let cat = Catalog::default_mssql_catalog(SchemaVariant::PreComputed);
        let entry = cat.lookup("HR.Employees").unwrap();
        assert!(entry.physical_table.columns.iter().any(|c| c.physical_name == "materialized_path"));
        assert!(entry.physical_table.columns.iter().any(|c| c.physical_name == "depth"));
    }

    #[test]
    fn test_variant_switch() {
        let mut cat = Catalog::default_mssql_catalog(SchemaVariant::Baseline);
        cat.switch_variant(SchemaVariant::ColumnarOptimized);
        assert_eq!(cat.variant(), SchemaVariant::ColumnarOptimized);
        let entry = cat.lookup("HR.Employees").unwrap();
        assert!(entry.physical_table.create_sql.contains("hr_employees_lob"));
    }

    #[test]
    fn test_ddl_generation() {
        let cat = Catalog::default_mssql_catalog(SchemaVariant::Baseline);
        let ddl = cat.ddl();
        assert!(ddl.contains("CREATE TABLE"));
        assert!(ddl.contains("hr_employees"));
        assert!(ddl.contains("sales_transactions"));
    }

    #[test]
    fn test_column_lookup() {
        let cat = Catalog::default_mssql_catalog(SchemaVariant::Baseline);
        let name = cat.physical_column_name("HR.Employees", "FullName").unwrap();
        assert_eq!(name, "FullName");
    }
}
