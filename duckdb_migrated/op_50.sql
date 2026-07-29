-- OP 50: System-versioned temporal with CHANGETABLE
-- Translated from T-SQL to DuckDB dialect

-- Query change tracking information
SELECT     CT.ProductID,
    CT.SYS_CHANGE_VERSION AS ChangeVersion,
    CT.SYS_CHANGE_OPERATION AS Operation,
    p.ProductName,
    p.BasePrice
FROM CHANGETABLE(CHANGES Sales.Products, 0) CT
LEFT JOIN Sales.Products p ON CT.ProductID = p.ProductID
LIMIT 50;
-- ============================================================================
-- BONUS: QUERY STORE ANALYSIS (MSSQL Unique Monitoring)
-- ============================================================================
SELECT     qsq.query_id,
    qsq.query_hash,
    qsrs.count_executions,
    qsrs.avg_duration / 1000.0 AS AvgDurationMs,
    qsrs.avg_cpu_time / 1000.0 AS AvgCpuMs,
    qsrs.avg_logical_io_reads AS AvgReads,
    qsrs.last_execution_time
FROM sys.query_store_query qsq
JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
WHERE qsrs.last_execution_time > (CURRENT_TIMESTAMP - INTERVAL '-1' DAY)
ORDER BY qsrs.avg_duration DESC
LIMIT 50;
-- ============================================================================
-- BONUS: PARTITION METADATA QUERY
-- ============================================================================
SELECT 
    OBJECT_NAME(p.object_id) AS TableName,
    p.partition_number,
    prv.value AS BoundaryValue,
    p.rows AS "RowCount"
FROM sys.partitions p
JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
LEFT JOIN sys.partition_range_values prv ON pf.function_id = prv.function_id 
    AND p.partition_number = prv.boundary_id + 1
WHERE p.object_id = OBJECT_ID('Sales.PartitionedSales')
AND p.index_id IN (0, 1)
ORDER BY p.partition_number
