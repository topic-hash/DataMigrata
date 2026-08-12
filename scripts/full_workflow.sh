#!/bin/bash
# Full workflow: apply patches, capture gold, export data
set -e
cd /workspaces/DataMigrata

echo "=== Step 1: Apply patches ==="
for f in scripts/patches/wave1_agent_A_views.sql scripts/patches/wave1_agent_B_func_views.sql scripts/patches/wave1_agent_C_views_index_proc.sql scripts/patches/wave1_agent_D_crypto_type_ct.sql; do
  echo "Applying $f..."
  docker exec -i mssql-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P YourStrong@Passw0rd -C -l 60 -t 300 -d MSSQL_Advanced_Demo -I < "$f" > /dev/null 2>&1
done
echo "Patches applied"

echo "=== Step 2: Capture gold standard ==="
rm -rf gold_standard
python3 scripts/capture_gold_v2.py 2>&1 | tail -5

echo "=== Step 3: Export data ==="
rm -rf mssql_data
python3 scripts/export_mssql_v2.py 2>&1 | tail -5

echo "=== DONE ==="
