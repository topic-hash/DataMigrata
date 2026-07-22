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

## File Reference

| File | When to Use |
|------|-------------|
| `sql/00_COMPLETE_MSSQL_Deployment.sql` | **First run** — creates everything |
| `sql/02_MSSQL_50_Operations_Expanded.sql` | **Second run** — 50 ops for expanded data |
| `sql/01_MSSQL_Migration_SyntheticData.sql` | Lightweight version (demo-sized data) |
| `sql/02_MSSQL_50_Sophisticated_Operations.sql` | Original ops for lightweight data |
| `docs/PROJECT_PLAN.md` | Architecture decisions and roadmap |
| `docker/docker-compose.yml` | Container orchestration |
