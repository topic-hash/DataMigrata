//! TNS (Transparent Network Substrate) server — accepts Oracle client connections.
//!
//! Greenfield: no production Rust TNS implementation exists. We implement enough
//! of the protocol to negotiate connections and accept SQL requests from
//! standard Oracle JDBC drivers, then forward the SQL through the translation
//! pipeline and relay the response.
//!
//! Reference: Oracle Net Services documentation, Babelfish for PostgreSQL
//! (which implements a subset of TDS for the inverse direction).

pub mod handshake;
pub mod data_types;
pub mod session;
