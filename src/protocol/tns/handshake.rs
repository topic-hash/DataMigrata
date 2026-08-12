//! TNS handshake — connection negotiation with Oracle clients.

/// TNS packet types (RFC: Oracle Net8 protocol).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TnsPacketType {
    Connect = 1,
    Accept = 2,
    Acknowledge = 3,
    Refuse = 4,
    Redirect = 5,
    Data = 6,
    NullData = 7,
    Abort = 9,
    Resend = 11,
    Marker = 12,
    Attention = 13,
    Control = 14,
}

/// TNS connection request from an Oracle client.
#[derive(Debug, Clone)]
pub struct ConnectRequest {
    pub version: u16,
    pub compatibility_version: u16,
    pub service_options: u16,
    pub session_data_unit_size: u16,
    pub transport_data_unit_size: u16,
    pub nt_protocol_chars: u16,
    pub line_turnaround: u16,
    pub value_of_1_in_hardware: u8,
    pub connect_data_length: u16,
    pub connect_data_offset: u16,
    pub max_receivable_connect_data: u32,
    pub connect_data: String,
}
