//! Phase 5 (future): Wire protocol layer.
//!
//! - **Incoming:** TNS server — accepts connections from Oracle JDBC/OCI clients.
//!   Uses `winnow` for zero-copy binary protocol parsing. This is greenfield
//!   work — no production Rust TNS implementation exists yet (knowledge base
//!   gap #4).
//! - **Outgoing:** TDS client — connects to MSSQL. Uses the `tiberius` crate
//!   (pure-Rust TDS client, async, tokio-native).
//!
//! # Why Rust (not Java/TypeScript)
//!
//! - No GC pauses — critical for tail latency on thousands of concurrent connections
//! - Zero-copy parsing via `winnow` — no buffer copies, no allocation pressure
//! - `tokio` async runtime — proven at RisingWave scale (~200K lines, 5-10x
//!   lower memory than equivalent Java systems)
//! - Memory safety without runtime cost — borrow checker eliminates ~70% of
//!   memory safety CVEs at compile time

pub mod tns;
pub mod tds;
