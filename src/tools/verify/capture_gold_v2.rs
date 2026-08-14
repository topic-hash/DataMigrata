//! Capture gold standard CSVs from MSSQL — v2 with QUOTED_IDENTIFIER ON prefix.
//!
//! Direct port of `scripts/capture_gold_v2.py`.
//!
//! Adds `SET QUOTED_IDENTIFIER ON` prefix and more SET options for correct
//! MSSQL behavior. Uses `-I` flag (quoted identifiers on).

use std::process::{Command, Stdio};
use std::time::Instant;

use super::capture_gold::CaptureConfig;
use super::super::common::csv_norm::md5_of_text;

/// SET prefix prepended to each op for correct MSSQL behavior.
const SET_PREFIX: &str = "SET QUOTED_IDENTIFIER ON;\n\
SET ANSI_NULLS ON;\n\
SET ANSI_PADDING ON;\n\
SET ANSI_WARNINGS ON;\n\
SET CONCAT_NULL_YIELDS_NULL ON;\n\
SET NOCOUNT ON;\n\
GO\n";

/// sqlcmd base command for v2 — adds `-I` flag (quoted identifiers on).
const SQLCMD_BASE: &[&str] = &[
    "docker",
    "exec",
    "-i",
    "mssql-test",
    "/opt/mssql-tools18/bin/sqlcmd",
    "-S",
    "localhost",
    "-U",
    "sa",
    "-P",
    "YourStrong@Passw0rd",
    "-C",
    "-l",
    "60",
    "-t",
    "120",
    "-d",
    "MSSQL_Advanced_Demo",
    "-I",  // quoted identifiers on
    "-W",  // trim trailing whitespace
    "-s", ",",  // column separator
    "-h", "-1", // no headers
    "-w", "65535", // wide rows
];

/// Run an op via sqlcmd with SET prefix.
fn run_op(sql_text: &str) -> (String, String, i32, f64) {
    let full_sql = format!("{}{}", SET_PREFIX, sql_text);
    let start = Instant::now();
    let mut child = match Command::new("docker")
        .args(&SQLCMD_BASE[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => return (String::new(), e.to_string(), -1, 0.0),
    };

    use std::io::Write;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(full_sql.as_bytes());
    }

    match child.wait_with_output() {
        Ok(output) => {
            let elapsed = start.elapsed().as_secs_f64();
            let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
            let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
            let code = output.status.code().unwrap_or(-1);
            (stdout, stderr, code, elapsed)
        }
        Err(e) => (String::new(), e.to_string(), -1, 0.0),
    }
}

/// Clean sqlcmd v2 output: strip noise lines.
fn clean_output(stdout: &str) -> Vec<String> {
    let mut cleaned: Vec<String> = Vec::new();
    for line in stdout.lines() {
        if line.starts_with("Changed database context")
            || line.starts_with("Msg ")
            || line.starts_with("Cmd ")
            || line.starts_with("DBCC")
        {
            continue;
        }
        let trimmed = line.trim_start();
        if trimmed.starts_with('(') && trimmed.contains("rows affected)") {
            continue;
        }
        if trimmed.starts_with("ALL 50") || trimmed.starts_with("=====") {
            continue;
        }
        cleaned.push(line.to_string());
    }
    while cleaned.last().map(|l| l.trim().is_empty()).unwrap_or(false) {
        cleaned.pop();
    }
    cleaned
}

/// Capture gold standard CSVs for all 50 ops (v2).
///
/// Direct port of `main()` from `capture_gold_v2.py`.
pub fn capture_all(config: &CaptureConfig) -> anyhow::Result<()> {
    let ops_dir = &config.ops_dir;
    let out_dir = &config.out_dir;
    std::fs::create_dir_all(out_dir)?;
    let mut summary: Vec<(u32, String, usize, String, f64, String)> = Vec::new();

    for op_num in 1..=50u32 {
        let op_file = ops_dir.join(format!("op_{:02}.sql", op_num));
        if !op_file.exists() {
            continue;
        }
        let sql_text = std::fs::read_to_string(&op_file)?;
        eprintln!("--- OP {:02} ---", op_num);

        let (stdout, stderr, exit_code, elapsed) = run_op(&sql_text);

        let cleaned = clean_output(&stdout);
        let out_csv = out_dir.join(format!("op_{:02}.csv", op_num));

        let csv_content = if cleaned.is_empty() {
            String::new()
        } else {
            format!("{}\n", cleaned.join("\n"))
        };
        std::fs::write(&out_csv, &csv_content)?;

        let hash = md5_of_text(&csv_content);
        let row_count = cleaned.len();

        let status = if exit_code == 0 && row_count > 0 {
            "OK"
        } else if row_count == 0 {
            "NO_RESULTS"
        } else {
            "FAIL"
        };
        // If exit_code != 0 but we have rows, still mark OK
        let status = if row_count > 0 && exit_code != 0 {
            "OK_WITH_WARNINGS"
        } else {
            status
        };
        let err_preview: String = stderr.chars().take(300).collect::<String>().replace('\n', " | ");
        eprintln!(
            "  {}  rows={}  hash={}  elapsed={:.2}s",
            status,
            row_count,
            &hash[..16.min(hash.len())],
            elapsed,
        );
        summary.push((
            op_num,
            status.to_string(),
            row_count,
            hash,
            elapsed,
            err_preview,
        ));
    }

    // Write summary
    let summary_path = out_dir.join("summary.csv");
    use std::io::Write;
    let mut f = std::fs::File::create(&summary_path)?;
    writeln!(f, "op_id,status,row_count,hash,elapsed_s,stderr")?;
    for (op_num, status, rc, h, el, err) in &summary {
        writeln!(f, "{},{},{},{},{:.2},\"{}\"", op_num, status, rc, h, el, err)?;
    }

    let ok = summary
        .iter()
        .filter(|s| s.1 == "OK" || s.1 == "OK_WITH_WARNINGS")
        .count();
    eprintln!("\n=== SUMMARY: {}/50 OK ===", ok);
    Ok(())
}
