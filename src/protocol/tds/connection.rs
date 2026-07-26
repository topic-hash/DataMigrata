//! TDS (Tabular Data Stream) client connection — connects to MSSQL.
//!
//! Wraps the `tiberius` crate (pure-Rust, async, tokio-native TDS client).

use std::time::Duration;
use tokio::net::TcpStream;
use tiberius::{Client, Config};

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
    /// Build a `tiberius::Config` from this connection spec.
    pub fn to_tiberius_config(&self) -> Config {
        let mut config = Config::new();
        config.host(&self.host);
        config.port(self.port);
        config.database(&self.database);
        config.authentication(tiberius::AuthMethod::sql_server(&self.username, &self.password));
        if self.encrypt {
            config.encrypt(tiberius::Encrypt::Required);
        }
        if self.trust_cert {
            config.trust_cert();
        }
        config
    }

    /// Establish a connection to MSSQL.
    ///
    /// Stub: real implementation calls `tiberius::Client::connect_named(config, tcp)`.
    pub async fn connect(&self) -> Result<(), String> {
        let _config = self.to_tiberius_config();
        let _tcp = TcpStream::connect(format!("{}:{}", self.host, self.port))
            .await
            .map_err(|e| e.to_string())?;
        // Real implementation: Client::connect_named(config, tcp).await
        Ok(())
    }
}
