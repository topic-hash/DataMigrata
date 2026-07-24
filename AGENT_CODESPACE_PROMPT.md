# Agent Instruction: Connecting to the Codespace

> **Purpose**: This file is a self-contained prompt. Copy its contents verbatim into any agent session to reliably SSH into the GitHub Codespace `symmetrical-tribble` and execute commands. No system `ssh` binary, `ssh-keygen`, or `sudo` is required — everything runs through Python + paramiko.

---

## THE PROMPT — Copy everything below this line

```
You need to SSH into a GitHub Codespace and execute commands. The environment you are running in has NO system `ssh` binary and NO root access. Do NOT attempt to install openssh, dropbear, or any ssh package. Do NOT use `gh codespace ssh` interactively — it will hang indefinitely on host-key prompts.

Instead, use the proven toolchain already in this repository. Follow these steps EXACTLY in order.

### Context
- Repository: https://github.com/topic-hash/DataMigrata (clone it if not already present)
- Codespace display name: `symmetrical-tribble`
- Codespace full machine name: `symmetrical-tribble-pjvp5rjg5w5v299jq`
- Working directory inside codespace: `/workspaces/DataMigrata`
- Docker compose directory: `/workspaces/DataMigrata/docker`

### How it works (READ THIS — do not skip)
The `gh` CLI has a `--stdio` mode (`gh cs ssh -c NAME --stdio`) that outputs a raw SSH transport stream on stdout. The Python script `tools/codespace_ssh.py` wraps this with **paramiko** (pure-Python SSH) via a `SubprocessSocket` adapter — no `ssh` binary needed at any point. A fake `ssh-keygen` script generates ECDSA keys via paramiko because `gh` calls `ssh-keygen` internally before opening the stdio stream.

This is the ONLY reliable method in environments without a system ssh binary.

### Step-by-step procedure

1. **Clone the repository** (if not already cloned):
   ```bash
   git clone https://github.com/topic-hash/DataMigrata.git
   cd DataMigrata
   ```

2. **Ensure paramiko is installed**:
   ```bash
   pip install paramiko -q
   ```

3. **Authenticate gh CLI** using the provided token:
   ```bash
   export GH_TOKEN="<TOKEN>"
   tools/bin/gh auth login --with-token <<< "<TOKEN>"
   ```
   Note: `tools/bin/gh` is a static x86_64 Linux binary (v2.63.2). Make it executable with `chmod +x tools/bin/gh` if needed.

4. **Verify the codespace exists** and check its state:
   ```bash
   tools/bin/gh codespace list
   ```

5. **If the codespace is in Shutdown/ShuttingDown state, start it**:
   ```bash
   tools/bin/gh api -X POST /user/codespaces/symmetrical-tribble-pjvp5rjg5w5v299jq/start
   ```
   Then poll until Available (check with `tools/bin/gh api /user/codespaces/symmetrical-tribble-pjvp5rjg5w5v299jq | python3 -c "import sys,json; print(json.load(sys.stdin)['state'])"`) — takes ~60-120 seconds.

6. **Execute commands on the codespace** using the Python SSH client:
   ```bash
   python3 tools/codespace_ssh.py \
     --token "<TOKEN>" \
     --codespace symmetrical-tribble \
     --command "<YOUR COMMAND HERE>"
   ```

   The `--codespace` flag accepts a partial match — `symmetrical-tribble` is sufficient; the script resolves it to the full name automatically.

   Increase timeout for long-running commands (e.g., docker pull) with `--timeout 600` (default is 300 seconds).

7. **After completing all work, close the connection** — the script handles cleanup automatically (kills subprocess, closes transport). If you want to stop the codespace entirely to save resources:
   ```bash
   tools/bin/gh api -X POST /user/codespaces/symmetrical-tribble-pjvp5rjg5w5v299jq/stop
   ```

### Common commands to run

**Start Docker containers (MSSQL):**
```bash
python3 tools/codespace_ssh.py \
  --token "<TOKEN>" \
  --codespace symmetrical-tribble \
  --command "cd /workspaces/DataMigrata/docker && docker compose up -d && docker compose ps"
```

**Check container status:**
```bash
python3 tools/codespace_ssh.py \
  --token "<TOKEN>" \
  --codespace symmetrical-tribble \
  --command "docker ps"
```

**Deploy SQL:**
```bash
python3 tools/codespace_ssh.py \
  --token "<TOKEN>" \
  --codespace symmetrical-tribble \
  --timeout 600 \
  --command "cd /workspaces/DataMigrata && /opt/mssql-tools/bin/sqlcmd -S localhost,1433 -U sa -P 'YourStrong@Passw0rd' -i sql/00_COMPLETE_MSSQL_Deployment.sql"
```

**Check database files:**
```bash
python3 tools/codespace_ssh.py \
  --token "<TOKEN>" \
  --codespace symmetrical-tribble \
  --command "ls -la /workspaces/DataMigrata/sql/"
```

### CRITICAL WARNINGS — Do NOT violate these

1. **Do NOT run `gh codespace ssh <name>` without `--stdio` and without wrapping in paramiko.** This will try to spawn a real `ssh` binary, which either does not exist or will hang on interactive prompts.

2. **Do NOT attempt to install any SSH package** (openssh-client, dropbear, etc.). There is no `sudo`. Static binary downloads of ssh are unreliable and unnecessary.

3. **Do NOT run `gh cs ssh -c NAME --stdio -- -i keyfile`**. The `--` flags cause `gh` to try spawning the real `ssh` binary. Use ONLY `gh cs ssh -c NAME --stdio` (no `--` separator).

4. **Do NOT use `ssh-keygen -t ed25519`**. The installed paramiko version may not support Ed25519. The script uses ECDSA (256-bit) which is fully supported.

5. **Do NOT set `channel.set_timeout()`** — use `channel.settimeout()` (lowercase `t`). This is a paramiko API quirk.

6. **The token will be revoked after the session.** Plan accordingly — do all work in one session, or obtain a new token.
```

---

## Notes for Humans

- **Token scopes needed**: `codespace` (SSH + management) and optionally `repo` (for git push/pull).
- **Token lifetime**: These tokens are single-use per session. Generate a new one from GitHub Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens.
- **The `<TOKEN>` placeholder** in the prompt above must be replaced with the actual token before sending to an agent.
- **Modifying the prompt**: If the codespace name changes, update the two hardcoded names (`symmetrical-tribble` and `symmetrical-tribble-pjvp5rjg5w5v299jq`) in the prompt and in `tools/codespace_ssh.py`.
