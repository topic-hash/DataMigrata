//! TDS (Tabular Data Stream) client — connects to MSSQL.
//!
//! NOTE: The `tiberius` crate was removed due to a compile conflict between
//! tiberius 0.12 and newer async-native-tls. We will either:
//! (a) wait for tiberius 0.13+ to fix the issue, or
//! (b) implement raw TDS protocol parsing using `winnow` (same approach as TNS).
//!
//! For now, this module is a placeholder. The 50-operations test does not
//! require a live MSSQL connection — it only verifies the SQL translation
//! pipeline end-to-end (parse → IR → optimize → generate T-SQL).

pub mod connection;
pub mod execute;
