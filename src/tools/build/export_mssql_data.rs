//! Export MSSQL tables/views to CSV via `docker exec sqlcmd`.
//!
//! Direct port of `scripts/export_mssql_data.py`.

use std::path::Path;
use std::process::{Command, Stdio};
use std::io::Write;

/// Tables to export.
pub const TABLES: &[(&str, &str)] = &[
    ("HR", "Employees"),
    ("HR", "OrgChart"),
    ("Sales", "Transactions"),
    ("Sales", "TransactionsHistory"),
    ("Sales", "Products"),
    ("Sales", "CustomerCache"),
    ("Sales", "HighSpeedLookup"),
    ("Sales", "PartitionedSales"),
    ("Archive", "OldTransactions"),
    ("Audit", "EventLog"),
    ("Security", "SensitiveData"),
    ("Staging", "ETLSource"),
];

/// Views to export.
pub const VIEWS: &[(&str, &str)] = &[
    ("Sales", "vw_ProductSummary"),
    ("Sales", "vw_AllTransactions"),
    ("HR", "vw_ActiveEmployees"),
    ("Sales", "vw_TransactionSummary"),
    ("Sales", "vw_EmployeeQuarterlySales"),
    ("Sales", "vw_NormalizedQuarterlySales"),
    ("HR", "vw_ManagerHierarchy"),
    ("Sales", "vw_MultiDimensionalSales"),
    ("Sales", "vw_RunningTotalsAndRanks"),
];

const SET_PREFIX: &str = "SET QUOTED_IDENTIFIER ON;\nSET ANSI_NULLS ON;\nSET NOCOUNT ON;\nGO\n";

/// Export a single table or view via sqlcmd.
///
/// Direct port of `export_table()` from `export_mssql_data.py`.
pub fn export_table(schema: &str, name: &str, out_dir: &Path) -> anyhow::Result<(usize, String)> {
    let query = format!("SELECT * FROM [{}].[{}]", schema, name);
    let full_sql = format!("{}{}", SET_PREFIX, query);

    let mut child = Command::new("docker")
        .args(&[
            "exec", "-i", "mssql-test",
            "/opt/mssql-tools18/bin/sqlcmd",
            "-S", "localhost", "-U", "sa", "-P", "YourStrong@Passw0rd",
            "-C", "-d", "MSSQL_Advanced_Demo",
            "-W", "-s", ",", "-h", "-1", "-w", "65535", "-r", "1",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(full_sql.as_bytes());
    }

    let output = child.wait_with_output()?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();

    // Clean output
    let cleaned: Vec<&str> = stdout
        .lines()
        .filter(|line| {
            !line.starts_with("Changed database context")
                && !line.starts_with("Msg ")
                && !line.starts_with("DBCC")
                && !(line.trim_start().starts_with('(') && line.contains("rows affected)"))
        })
        .collect();

    let out_path = out_dir.join(format!("{}_{}.csv", schema, name));
    let csv_content = if cleaned.is_empty() {
        String::new()
    } else {
        format!("{}\n", cleaned.join("\n"))
    };
    std::fs::write(&out_path, &csv_content)?;

    Ok((cleaned.len(), stderr))
}

/// Export all tables and views.
///
/// Direct port of `main()` from `export_mssql_data.py`.
pub fn export_all(out_dir: &Path) -> anyhow::Result<()> {
    std::fs::create_dir_all(out_dir)?;

    eprintln!("=== TABLES ===");
    for (schema, name) in TABLES {
        let (rows, stderr) = export_table(schema, name, out_dir)?;
        eprintln!("  {}.{}: {} rows", schema, name, rows);
        if !stderr.is_empty() {
            eprintln!("    stderr: {}", &stderr[..200.min(stderr.len())]);
        }
    }

    eprintln!("=== VIEWS ===");
    for (schema, name) in VIEWS {
        let (rows, stderr) = export_table(schema, name, out_dir)?;
        eprintln!("  {}.{}: {} rows", schema, name, rows);
        if !stderr.is_empty() {
            eprintln!("    stderr: {}", &stderr[..200.min(stderr.len())]);
        }
    }

    Ok(())
}
