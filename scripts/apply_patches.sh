#!/bin/bash
cd /workspaces/DataMigrata
for f in scripts/patches/wave1_agent_A_views.sql scripts/patches/wave1_agent_B_func_views.sql scripts/patches/wave1_agent_C_views_index_proc.sql scripts/patches/wave1_agent_D_crypto_type_ct.sql; do
  echo "=== APPLY $f ==="
  docker exec -i mssql-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P YourStrong@Passw0rd -C -l 60 -t 300 -d MSSQL_Advanced_Demo -I < "$f" 2>&1 | grep -E "Msg|Error" | head -10
  echo "exit=$?"
done
echo "=== Verify objects ==="
docker exec mssql-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P YourStrong@Passw0rd -C -d MSSQL_Advanced_Demo -Q "SELECT 'VIEW' AS type, schema_name(t.schema_id)+'.'+t.name AS name FROM sys.views t UNION ALL SELECT 'PROC', schema_name(p.schema_id)+'.'+p.name FROM sys.procedures p UNION ALL SELECT 'FN', schema_name(f.schema_id)+'.'+f.name FROM sys.objects f WHERE f.type IN ('FN','IF','TF') ORDER BY 1,2" -W -s ',' -h -1 2>&1 | head -30
