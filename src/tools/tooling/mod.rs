//! GROUP F — Tooling scripts (deprecated — replaced by codespacectl).
//!
//! Ports of:
//! - `tools/codespace_ssh.py` → [`codespace_ssh`]
//! - `tools/setup.py` → [`setup`]
//!
//! These modules are preserved for backward compatibility but should be
//! considered deprecated — `codespacectl` replaces them.

pub mod codespace_ssh;
pub mod setup;
