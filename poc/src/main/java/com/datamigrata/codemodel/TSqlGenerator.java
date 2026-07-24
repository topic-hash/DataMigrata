/*
 * DataMigrata PoC — T-SQL Code Generator (Phase 4)
 *
 * Generates T-SQL from Calcite RelNode tree using
 * SqlDialect pretty-printing via RelToSqlConverter.
 */

package com.datamigrata.codemodel;

import org.apache.calcite.rel.RelNode;
import org.apache.calcite.rel.RelWriter;
import org.apache.calcite.rel.externalize.RelJsonWriter;
import org.apache.calcite.rel.rel2sql.RelToSqlConverter;
import org.apache.calcite.sql.SqlDialect;
import org.apache.calcite.sql.SqlNode;
import org.apache.calcite.sql.dialect.MssqlSqlDialect;
import org.apache.calcite.sql.pretty.SqlPrettyWriter;

import java.util.ArrayList;
import java.util.List;

/**
 * Phase 4: Generate T-SQL from optimized RelNode tree.
 *
 * Uses Calcite's RelToSqlConverter which dispatches
 * via reflection to type-specific visit methods.
 * For nodes it can't convert, falls back to Calcite's
 * RelWriter explanation.
 */
public class TSqlGenerator {

    public CodeGenerationResult generate(RelNode relNode) {
        if (relNode == null) {
            return CodeGenerationResult.failure("RelNode is null");
        }

        try {
            SqlDialect dialect = MssqlSqlDialect.DEFAULT;

            RelToSqlConverter converter = new RelToSqlConverter(dialect);
            SqlNode sqlNode = converter.visit(relNode).asStatement();

            SqlPrettyWriter writer = new SqlPrettyWriter(dialect);
            sqlNode.unparse(writer, 0, 0);
            String tsql = writer.toString();

            List<String> warnings = new ArrayList<>();
            tsql = postProcessForMssql(tsql, warnings);

            return new CodeGenerationResult(tsql, true, warnings, null);
        } catch (Throwable e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            String msg = cause.getMessage();

            // If RelToSql fails (e.g., unsupported node type),
            // fall back to Calcite's RelWriter explanation
            try {
                String fallback = relNode.explain();
                List<String> warnings = new ArrayList<>();
                warnings.add("Used Calcite explain fallback (full SQL generation not yet supported for this node type)");
                return new CodeGenerationResult(fallback, true, warnings, null);
            } catch (Exception ex2) {
                return CodeGenerationResult.failure("Code gen error: " + msg);
            }
        }
    }

    private String postProcessForMssql(String tsql, List<String> warnings) {
        String result = tsql;
        if (result.contains("CURRENT_TIMESTAMP")) {
            result = result.replace("CURRENT_TIMESTAMP", "GETDATE()");
            warnings.add("CURRENT_TIMESTAMP → GETDATE()");
        }
        return result.trim();
    }
}
