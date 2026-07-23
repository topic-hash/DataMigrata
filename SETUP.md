# Setup Guide

## Quick Start (5 minutes)

### 1. Start SQL Server (Docker)

```bash
cd docker
docker-compose up -d
cd ..
```

Wait 30 seconds for the database engine to initialize.

### 2. Install VS Code + MSSQL Extension

1. Download VS Code: https://code.visualstudio.com/download
2. Open Extensions view (`Ctrl+Shift+X`)
3. Search `mssql` → Install **SQL Server (mssql)** by Microsoft

### 3. Connect to the Database

In VS Code:
- Press `F1` → **MS SQL: Manage Connection Profile**
- **Server name:** `localhost,1433`
- **Authentication type:** SQL Login
- **User name:** `sa`
- **Password:** `YourStrong@Passw0rd`
- **Save Password:** Yes
- **Profile Name:** `MSSQL Advanced Demo`

### 4. Deploy the Database

1. Open `sql/00_COMPLETE_MSSQL_Deployment.sql`
2. Press `Ctrl+Shift+E` to execute
3. Wait ~2 minutes for all tables and data to be created

### 5. Run the 50 Operations

1. Open `sql/02_MSSQL_50_Operations_Expanded.sql`
2. Execute category by category
3. Observe results in the output panel

---

## Codespace Remote Access (from AI agent / headless environments)

The `tools/` directory contains everything needed to SSH into the GitHub Codespace and run commands **without any system packages** (no ssh, no ssh-keygen, no sudo required).

### How it works

The `gh` binary (v2.63.2, static x86_64 Linux) uses its `--stdio` mode to provide a raw SSH transport over stdin/stdout. The Python script (`codespace_ssh.py`) wraps this with `paramiko` to execute commands remotely.

### Bootstrap (one-time per session)

```bash
python3 tools/setup.py --token ghp_YOUR_TOKEN
```

This will:
1. Install paramiko (if missing)
2. Authenticate the gh CLI
3. Start the codespace if shut down
4. Print ready-to-use commands

### Run commands on the codespace

```bash
python3 tools/codespace_ssh.py \
  --token ghp_YOUR_TOKEN \
  --codespace symmetrical-tribble \
  --command "cd /workspaces/DataMigrata/docker && docker compose up -d && docker compose ps"
```

### Stop the codespace

```bash
GH_TOKEN=ghp_YOUR_TOKEN tools/bin/gh api -X POST /user/codespaces/symmetrical-tribble-pjvp5rjg5w5v299jq/stop
```

### Token requirements

- `codespace` scope — for `gh cs ssh --stdio` and codespace management
- `repo` scope — for pushing code to this repository
- Tokens should be revoked after each session

---

## File Reference

| File | When to Use |
|------|-------------|
| `sql/00_COMPLETE_MSSQL_Deployment.sql` | **First run** — creates everything |
| `sql/02_MSSQL_50_Operations_Expanded.sql` | **Second run** — 50 ops for expanded data |
| `sql/01_MSSQL_Migration_SyntheticData.sql` | Lightweight version (demo-sized data) |
| `sql/02_MSSQL_50_Sophisticated_Operations.sql` | Original ops for lightweight data |
| `docs/PROJECT_PLAN.md` | Architecture decisions and roadmap |
| `docker/docker-compose.yml` | Container orchestration |
| `tools/setup.py` | Bootstrap script — installs deps, auths gh, starts codespace |
| `tools/codespace_ssh.py` | SSH client — runs commands on the codespace via Python |
| `tools/bin/gh` | GitHub CLI binary (static, no installation needed) |
