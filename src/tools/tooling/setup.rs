//! Bootstrap script — check dependencies, authenticate, start codespace.
//!
//! Direct port of `tools/setup.py`.
//!
//! Deprecated — use `codespacectl` instead.

use std::process::Command;

use super::codespace_ssh::{auth_gh, ensure_codespace_running, find_gh_bin};

/// Check dependencies.
///
/// Direct port of `check_dependencies()` from `setup.py`.
pub fn check_dependencies() -> anyhow::Result<()> {
    eprintln!("Python: {}", "Rust (native — no Python needed)");
    if let Some(gh_bin) = find_gh_bin() {
        eprintln!("gh: {}", gh_bin);
        let output = Command::new(&gh_bin).arg("--version").output()?;
        eprintln!("  version: {}", String::from_utf8_lossy(&output.stdout).trim());
    } else {
        eprintln!("WARNING: gh binary not found");
    }
    Ok(())
}

/// Start codespace and print usage.
///
/// Direct port of `main()` from `setup.py`.
pub fn run(token: &str, codespace: &str, skip_auth: bool, skip_start: bool) -> anyhow::Result<()> {
    std::env::set_var("GH_TOKEN", token);

    check_dependencies()?;

    let gh_bin = find_gh_bin().ok_or_else(|| anyhow::anyhow!("gh binary not found"))?;

    if !skip_auth {
        auth_gh(&gh_bin, token)?;
        eprintln!("Authenticated.");
    }

    if !skip_start {
        let full_name = ensure_codespace_running(&gh_bin, codespace)?;
        eprintln!("\nCodespace ready: {}", full_name);
        eprintln!("\nUsage:");
        eprintln!("  {} cs ssh -c {}", gh_bin, full_name);
    }

    Ok(())
}
