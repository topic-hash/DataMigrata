//! SSH into GitHub Codespace via `gh cs ssh --stdio`.
//!
//! Direct port of `tools/codespace_ssh.py`.
//!
//! Deprecated — use `codespacectl` instead.

use std::process::{Command, Stdio};
use std::io::Write;

/// Find the gh binary.
///
/// Direct port of `find_gh_bin()` from `codespace_ssh.py`.
pub fn find_gh_bin() -> Option<String> {
    // Check tools/bin/gh first
    let local = std::path::Path::new("tools/bin/gh");
    if local.exists() {
        return Some(local.to_string_lossy().into_owned());
    }
    // Check PATH
    if let Ok(output) = Command::new("which").arg("gh").output() {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return Some(path);
            }
        }
    }
    None
}

/// Authenticate gh CLI with token.
///
/// Direct port of `auth_gh()` from `codespace_ssh.py`.
pub fn auth_gh(gh_bin: &str, token: &str) -> anyhow::Result<()> {
    let mut child = Command::new(gh_bin)
        .args(&["auth", "login", "--with-token"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(token.as_bytes())?;
    }
    let output = child.wait_with_output()?;
    if !output.status.success() {
        anyhow::bail!("gh auth login failed: {}", String::from_utf8_lossy(&output.stderr));
    }
    Ok(())
}

/// Ensure codespace is running, start if needed.
///
/// Direct port of `ensure_codespace_running()` from `codespace_ssh.py`.
pub fn ensure_codespace_running(gh_bin: &str, codespace_name: &str) -> anyhow::Result<String> {
    // List codespaces
    let output = Command::new(gh_bin)
        .args(&["codespace", "list", "--json", "name,state,displayName"])
        .output()?;
    let json: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let mut full_name = String::new();
    let mut state = String::new();

    if let Some(arr) = json.as_array() {
        for cs in arr {
            let name = cs.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let display = cs.get("displayName").and_then(|v| v.as_str()).unwrap_or("");
            if name.contains(codespace_name) || display.contains(codespace_name) {
                full_name = name.to_string();
                state = cs.get("state").and_then(|v| v.as_str()).unwrap_or("").to_string();
                break;
            }
        }
    }

    if full_name.is_empty() {
        anyhow::bail!("codespace '{}' not found", codespace_name);
    }

    // Start if shutdown
    if state == "Shutdown" || state == "ShuttingDown" {
        eprintln!("Starting codespace {}...", full_name);
        let _ = Command::new(gh_bin)
            .args(&["api", "--method", "POST", &format!("/user/codespaces/{}/start", full_name)])
            .output()?;
        // Poll until available
        for _ in 0..40 {
            std::thread::sleep(std::time::Duration::from_secs(5));
            let output = Command::new(gh_bin)
                .args(&["codespace", "list", "--json", "name,state"])
                .output()?;
            if let Ok(json) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
                if let Some(arr) = json.as_array() {
                    for cs in arr {
                        let name = cs.get("name").and_then(|v| v.as_str()).unwrap_or("");
                        if name == full_name {
                            let s = cs.get("state").and_then(|v| v.as_str()).unwrap_or("");
                            if s == "Available" {
                                eprintln!("Codespace is available.");
                                return Ok(full_name);
                            }
                        }
                    }
                }
            }
        }
        anyhow::bail!("codespace did not become available after 200s");
    }

    Ok(full_name)
}

/// Execute a command in the codespace via SSH.
///
/// Direct port of `ssh_exec()` from `codespace_ssh.py`.
///
/// NOTE: The Python version uses paramiko for SSH transport. In the Rust
/// port, we use `gh cs ssh` directly, which handles the SSH connection.
pub fn ssh_exec(gh_bin: &str, codespace_full_name: &str, command: &str) -> anyhow::Result<(String, String, i32)> {
    let output = Command::new(gh_bin)
        .args(&["cs", "ssh", "-c", codespace_full_name, "--", command])
        .output()?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);
    Ok((stdout, stderr, code))
}
