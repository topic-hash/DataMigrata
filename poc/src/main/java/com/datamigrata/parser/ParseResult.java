package com.datamigrata.parser;

import org.apache.calcite.sql.SqlNode;

import java.util.List;
import java.util.ArrayList;

/**
 * Result of parsing an Oracle SQL statement.
 */
public class ParseResult {
    private final boolean success;
    private final String originalSql;
    private final String preprocessedSql;
    private final SqlNode parseTree;
    private final String statementType;
    private final List<String> errors;
    private final List<String> preprocessWarnings;

    public ParseResult(boolean success, String originalSql, String preprocessedSql,
                       SqlNode parseTree, String statementType,
                       List<String> errors, List<String> preprocessWarnings) {
        this.success = success;
        this.originalSql = originalSql;
        this.preprocessedSql = preprocessedSql;
        this.parseTree = parseTree;
        this.statementType = statementType;
        this.errors = errors;
        this.preprocessWarnings = preprocessWarnings;
    }

    public static ParseResult failure(String sql, String error) {
        List<String> errors = new ArrayList<>();
        errors.add(error);
        return new ParseResult(false, sql, sql, null, "UNKNOWN", errors, new ArrayList<>());
    }

    public boolean isSuccess() { return success; }
    public String getOriginalSql() { return originalSql; }
    public String getPreprocessedSql() { return preprocessedSql; }
    public SqlNode getParseTree() { return parseTree; }
    public String getStatementType() { return statementType; }
    public List<String> getErrors() { return errors; }
    public List<String> getPreprocessWarnings() { return preprocessWarnings; }

    @Override
    public String toString() {
        return "ParseResult{success=" + success
                + ", type=" + statementType
                + ", errors=" + errors.size()
                + ", warnings=" + preprocessWarnings.size()
                + "}";
    }
}
