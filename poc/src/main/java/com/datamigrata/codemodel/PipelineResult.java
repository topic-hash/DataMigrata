package com.datamigrata.codemodel;

import java.util.List;
import java.util.ArrayList;

/**
 * Result of the complete Oracle→MSSQL translation pipeline.
 */
public class PipelineResult {
    private final String originalOracleSql;
    private final String preprocessedSql;
    private final String generatedTsql;
    private final boolean success;
    private final List<String> errors;
    private final List<String> warnings;
    private final List<String> rulesApplied;
    private final long translationTimeMs;

    public PipelineResult(String originalOracleSql, String preprocessedSql,
                          String generatedTsql, boolean success,
                          List<String> errors, List<String> warnings,
                          List<String> rulesApplied, long translationTimeMs) {
        this.originalOracleSql = originalOracleSql;
        this.preprocessedSql = preprocessedSql;
        this.generatedTsql = generatedTsql;
        this.success = success;
        this.errors = errors;
        this.warnings = warnings;
        this.rulesApplied = rulesApplied;
        this.translationTimeMs = translationTimeMs;
    }

    public static PipelineResult failure(String oracleSql, String error, long elapsed) {
        List<String> errors = new ArrayList<>();
        errors.add(error);
        return new PipelineResult(oracleSql, oracleSql, null, false,
                errors, new ArrayList<>(), new ArrayList<>(), elapsed);
    }

    public String getOriginalOracleSql() { return originalOracleSql; }
    public String getPreprocessedSql() { return preprocessedSql; }
    public String getGeneratedTsql() { return generatedTsql; }
    public boolean isSuccess() { return success; }
    public List<String> getErrors() { return errors; }
    public List<String> getWarnings() { return warnings; }
    public List<String> getRulesApplied() { return rulesApplied; }
    public long getTranslationTimeMs() { return translationTimeMs; }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append("=== Pipeline Result ===\n");
        sb.append("Success: ").append(success).append("\n");
        sb.append("Oracle: ").append(originalOracleSql).append("\n");
        if (generatedTsql != null) {
            sb.append("T-SQL: ").append(generatedTsql).append("\n");
        }
        if (!errors.isEmpty()) {
            sb.append("Errors: ").append(errors).append("\n");
        }
        if (!warnings.isEmpty()) {
            sb.append("Warnings: ").append(warnings).append("\n");
        }
        if (!rulesApplied.isEmpty()) {
            sb.append("Rules Applied: ").append(rulesApplied).append("\n");
        }
        sb.append("Time: ").append(translationTimeMs).append("ms");
        return sb.toString();
    }
}
