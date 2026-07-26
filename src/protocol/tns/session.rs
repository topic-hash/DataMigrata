//! TNS session — represents one client connection.

use std::net::SocketAddr;

/// A live TNS session with an Oracle client.
#[derive(Debug)]
pub struct TnsSession {
    /// Client's network address.
    pub peer_addr: SocketAddr,
    /// Service name the client requested (e.g., `ORCLPDB1`).
    pub service_name: String,
    /// Whether the session has completed TNS handshake.
    pub authenticated: bool,
}

impl TnsSession {
    pub fn new(peer_addr: SocketAddr, service_name: String) -> Self {
        Self {
            peer_addr,
            service_name,
            authenticated: false,
        }
    }
}
