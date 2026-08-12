//! TDS query execution — runs T-SQL against MSSQL and returns results.
//!
//! Stub: real implementation uses `tiberius::Client::query` / `simple_query`.

pub struct ExecuteResult {
    pub rows_affected: u64,
}

/// Execute a T-SQL statement against the connected MSSQL instance.
///
/// Stub: real implementation:
/// ```ignore
/// let mut stream = client.query(tsql, &[]).await?;
/// while let Some(row) = stream.into_row().await? { ... }
/// ```
pub async fn execute_tsql(_tsql: &str) -> Result<ExecuteResult, String> {
    Ok(ExecuteResult { rows_affected: 0 })
}
