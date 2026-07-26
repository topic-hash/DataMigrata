//! TDS (Tabular Data Stream) client connection — connects to MSSQL.
//!
//! NOTE: The `tiberius` crate was removed due to a compile conflict between
//! tiberius 0.12 and newer async-native-tls. We will either:
//! (a) wait for tiberius 0.13+ to fix the issue, or
//! (b) implement raw TDS protocol parsing using `winnow` (same approach as TNS).
//!
//! For now, this module is a placeholder. The 50-operations test does not
//! require a live MSSQL connection — it only verifies the SQL translation
//! pipeline end-to-end (parse → IR → optimize → generate T-SQL).

use std::time::Duration;

/// A configured but not-yet-connected TDS client.
#[derive(Debug, Clone)]
pub struct TdsConnection {
    pub host: String,
    pub port: u16,
    pub database: String,
    pub username: String,
    pub password: String,
    pub encrypt: bool,
    pub trust_cert: bool,
    pub connect_timeout: Duration,
}

impl TdsConnection {
    pub fn new(host: impl Into<String>, port: u16, database: impl Into<String>) -> Self {
        Self {
            host: host.into(),
            port,
            database: database.into(),
            username: String::new(),
            password: String::new(),
            encrypt: false,
            trust_cert: false,
            connect_timeout: Duration::from_secs(30),
        }
    }

    /// Establish a connection to MSSQL.
    ///
    /// Stub: real implementation will use either tiberius 0.13+ (when released)
    /// or a hand-rolled TDS client using `winnow` for zero-copy parsing.
    pub async fn connect(&self) -> Result<(), String> {
        Err("TDS client not yet wired up — see module docs".to_string())
    }
}
