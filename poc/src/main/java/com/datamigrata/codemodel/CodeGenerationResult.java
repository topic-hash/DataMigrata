package com.datamigrata.codemodel;

import java.util.List;
import java.util.ArrayList;

/**
 * Result of T-SQL code generation (Phase 4).
 */
public class CodeGenerationResult {
    private final String tsql;
    private final boolean success;
    private final List<String> warnings;
    private final String errorMessage;

    public CodeGenerationResult(String tsql, boolean success,
                               List<String> warnings, String errorMessage) {
        this.tsql = tsql;
        this.success = success;
        this.warnings = warnings;
        this.errorMessage = errorMessage;
    }

    public static CodeGenerationResult failure(String error) {
        return new CodeGenerationResult(null, false, new ArrayList<>(), error);
    }

    public String getTsql() { return tsql; }
    public boolean isSuccess() { return success; }
    public List<String> getWarnings() { return warnings; }
    public String getErrorMessage() { return errorMessage; }

    @Override
    public String toString() {
        return "CodeGenResult{success=" + success
                + (tsql != null ? ", sql=" + tsql.substring(0, Math.min(tsql.length(), 80)) : "")
                + (errorMessage != null ? ", error=" + errorMessage : "")
                + "}";
    }
}
