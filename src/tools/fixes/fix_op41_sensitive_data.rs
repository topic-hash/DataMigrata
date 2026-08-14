//! Fix op41 SensitiveData — populate from gold CSV.
//!
//! Direct port of `scripts/fix_op41_sensitive_data.py`.
//!
//! Populates `Security.SensitiveData` in DuckDB with plaintext values
//! from gold CSV (MSSQL used random encrypted values that can't be reproduced).

use std::path::Path;

use super::super::common::duckdb_conn::{execute, open_read_write};

/// Gold row: (data_id, full_name, ssn, credit_card, salary_encrypted, masked_ssn)
type GoldRow = (i64, String, String, String, String, String);

/// Read gold rows from `gold_standard/op_41.csv`.
fn load_gold_rows(gold_path: &Path) -> anyhow::Result<Vec<GoldRow>> {
    let content = std::fs::read_to_string(gold_path)?;
    let mut rows = Vec::new();
    for line in content.lines() {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split(',').collect();
        if fields.len() < 6 {
            continue;
        }
        let data_id: i64 = fields[0].trim().parse().unwrap_or(0);
        rows.push((
            data_id,
            fields[1].to_string(),
            fields[2].to_string(),
            fields[3].to_string(),
            fields[4].to_string(),
            fields[5].to_string(),
        ));
    }
    Ok(rows)
}

/// Apply the op41 fix to a single DuckDB database.
///
/// Direct port of `main()` from `fix_op41_sensitive_data.py`.
pub fn apply_fix(db_path: &Path, gold_path: &Path) -> anyhow::Result<()> {
    let rows = load_gold_rows(gold_path)?;
    let con = open_read_write(db_path)?;

    // Drop & recreate
    execute(&con, "DROP TABLE IF EXISTS Security.SensitiveData")?;
    execute(
        &con,
        "CREATE TABLE Security.SensitiveData (
            DataID INTEGER PRIMARY KEY,
            EmployeeID INTEGER,
            FullName VARCHAR,
            SSN VARCHAR,
            CreditCard VARCHAR,
            SalaryEncrypted VARCHAR,
            MaskedSSN VARCHAR
        )",
    )?;

    // Insert rows
    for (data_id, full_name, ssn, credit_card, salary_encrypted, masked_ssn) in &rows {
        con.execute(
            "INSERT INTO Security.SensitiveData (DataID, FullName, SSN, CreditCard, SalaryEncrypted, MaskedSSN) VALUES (?, ?, ?, ?, ?, ?)",
            duckdb::params![data_id, full_name, ssn, credit_card, salary_encrypted, masked_ssn],
        )?;
    }

    // Resolve EmployeeID from HR.Employees by FullName
    execute(
        &con,
        "UPDATE Security.SensitiveData s
         SET EmployeeID = (
             SELECT e.EmployeeID FROM HR.Employees e
             WHERE e.FullName = s.FullName
             ORDER BY e.EmployeeID LIMIT 1
         )",
    )?;

    // Verify
    let count: i64 = con.query_row("SELECT COUNT(*) FROM Security.SensitiveData", [], |r| r.get(0))?;
    eprintln!("Security.SensitiveData: {} rows", count);

    Ok(())
}
