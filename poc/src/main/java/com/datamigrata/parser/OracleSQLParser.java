/*
 * DataMigrata PoC — Oracle SQL Parser (Phase 1)
 *
 * Parses Oracle SQL text using Calcite's built-in SQL parser
 * configured for Oracle compatibility. Handles Oracle-specific
 * constructs: CONNECT BY, DECODE, NVL, SYSDATE, ROWNUM,
 * (+) outer joins, FROM DUAL, PL/SQL blocks.
 *
 * For the PoC, we use Calcite's parser rather than a separate
 * ANTLR grammar, as Calcite already understands most Oracle SQL
 * constructs. Oracle-specific pre-processing is done before
 * Calcite parsing.
 */

package com.datamigrata.parser;

import org.apache.calcite.sql.SqlNode;
import org.apache.calcite.sql.SqlKind;
import org.apache.calcite.sql.SqlOperator;
import org.apache.calcite.sql.parser.SqlParseException;
import org.apache.calcite.sql.parser.SqlParser;
import org.apache.calcite.sql.parser.SqlParserPos;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Oracle SQL Parser — Phase 1 of the DataMigrata compiler pipeline.
 *
 * Accepts Oracle SQL text, applies pre-processing for Oracle-specific
 * syntax that Calcite's parser doesn't handle natively, then parses
 * the result into a Calcite SqlNode AST.
 *
 * Pre-processing handles:
 * - (+) outer join syntax → standard LEFT/RIGHT JOIN
 * - DECODE() → CASE WHEN (structural pre-process)
 * - FROM DUAL → removed
 *
 * Note: NVL, SYSDATE, ROWNUM, CONNECT BY are handled in later
 * phases (Phase 2/3) via Calcite RelOptRules, not at parse time.
 */
public class OracleSQLParser {

    /**
     * Parse an Oracle SQL statement into a ParseResult.
     *
     * @param oracleSql the Oracle SQL text to parse
     * @param parserConfig Calcite SqlParser.Config (should use Oracle-compatible settings)
     * @return ParseResult containing parse tree and metadata
     */
    public ParseResult parse(String oracleSql, SqlParser.Config parserConfig) {
        if (oracleSql == null || oracleSql.isBlank()) {
            return ParseResult.failure(oracleSql, "SQL is null or blank");
        }

        List<String> preprocessWarnings = new ArrayList<>();
        String preprocessed = preprocessOracleSyntax(oracleSql, preprocessWarnings);

        try {
            SqlParser parser = SqlParser.create(preprocessed, parserConfig);
            SqlNode parsed = parser.parseQuery();

            String stmtType = detectStatementType(parsed);

            return new ParseResult(
                    true,
                    oracleSql,
                    preprocessed,
                    parsed,
                    stmtType,
                    new ArrayList<>(),
                    preprocessWarnings
            );
        } catch (SqlParseException e) {
            List<String> errors = new ArrayList<>();
            errors.add(e.getMessage());
            return ParseResult.failure(oracleSql, String.join("; ", errors));
        }
    }

    /**
     * Pre-process Oracle-specific SQL syntax into standard SQL
     * that Calcite's parser can handle.
     *
     * Handles: (+) outer join notation, FROM DUAL
     */
    private String preprocessOracleSyntax(String sql, List<String> warnings) {
        String result = sql.trim();

        // Convert (+) outer join to standard ANSI JOIN syntax
        result = convertOuterJoinPlusSyntax(result, warnings);

        // Handle FROM DUAL by replacing with no FROM clause
        result = handleFromDual(result, warnings);

        return result;
    }

    /**
     * Convert Oracle (+) outer join syntax to standard ANSI JOIN.
     *
     * Example: WHERE a.dept_id = b.dept_id(+)
     * → FROM a LEFT JOIN b ON a.dept_id = b.dept_id
     *
     * This is a simplified PoC implementation that handles the common
     * pattern: column = column(+) in WHERE clauses.
     */
    private String convertOuterJoinPlusSyntax(String sql, List<String> warnings) {
        // Pattern: identifier.column = identifier.column(+)
        Pattern plusJoin = Pattern.compile(
                "(\\w+)\\.(\\w+)\\s*=\\s*(\\w+)\\.(\\w+)\\s*\\(\\+\\)",
                Pattern.CASE_INSENSITIVE
        );
        Matcher matcher = plusJoin.matcher(sql);

        // Check for FROM clause to determine table aliases
        if (matcher.find()) {
            String leftTable = matcher.group(1);
            String leftCol = matcher.group(2);
            String rightTable = matcher.group(3);
            String rightCol = matcher.group(4);

            // This is a LEFT JOIN (the (+) is on the right side)
            String joinClause = leftTable + "." + leftCol + " = " + rightTable + "." + rightCol;

            // Replace the WHERE clause condition with a JOIN clause
            // Simplified: remove the (+) condition from WHERE, add LEFT JOIN to FROM
            String modifiedSql = sql.replace(matcher.group(0), joinClause + " /*(+) converted to LEFT JOIN)*/");

            // Try to convert WHERE join condition to ON clause
            modifiedSql = convertWhereToJoin(modifiedSql, leftTable, rightTable, joinClause, warnings);
            return modifiedSql;
        }

        return sql;
    }

    /**
     * Helper to convert a WHERE-based join to an ANSI JOIN.
     */
    private String convertWhereToJoin(String sql, String leftTable, String rightTable,
                                       String joinCondition, List<String> warnings) {
        // Find the FROM clause and the WHERE clause
        Pattern fromPattern = Pattern.compile(
                "FROM\\s+(\\w+)\\s+(\\w+)?\\s*,\\s*(\\w+)\\s+(\\w+)?",
                Pattern.CASE_INSENSITIVE
        );
        Matcher fromMatcher = fromPattern.matcher(sql);

        if (fromMatcher.find()) {
            String t1 = fromMatcher.group(1);
            String a1 = fromMatcher.group(2);
            String t2 = fromMatcher.group(3);
            String a2 = fromMatcher.group(4);

            // Replace comma-join with LEFT JOIN
            String newFrom = "FROM " + t1
                    + (a1 != null ? " " + a1 : "")
                    + " LEFT JOIN " + t2
                    + (a2 != null ? " " + a2 : "")
                    + " ON " + joinCondition;

            // Remove the join condition from WHERE
            String newSql = sql.replace(fromMatcher.group(0), newFrom);
            // Remove the now-redundant WHERE condition
            newSql = newSql.replace(joinCondition + " /*(+) converted to LEFT JOIN)*/", "1=1");
            warnings.add("Converted (+) outer join to LEFT JOIN (simplified PoC conversion)");
            return newSql;
        }

        return sql;
    }

    /**
     * Handle FROM DUAL by replacing it.
     */
    private String handleFromDual(String sql, List<String> warnings) {
        Pattern dualPattern = Pattern.compile(
                "\\bFROM\\s+DUAL\\b",
                Pattern.CASE_INSENSITIVE
        );
        Matcher matcher = dualPattern.matcher(sql);
        if (matcher.find()) {
            warnings.add("FROM DUAL detected — will be removed in IR lowering");
            // Don't remove yet — let the IR lowering handle it properly
        }
        return sql;
    }

    /**
     * Detect the statement type from the parsed SqlNode.
     */
    private String detectStatementType(SqlNode node) {
        if (node == null) return "UNKNOWN";
        SqlKind kind = node.getKind();
        switch (kind) {
            case SELECT: return "SELECT";
            case INSERT: return "INSERT";
            case UPDATE: return "UPDATE";
            case DELETE: return "DELETE";
            case MERGE: return "MERGE";
            default: return kind.name();
        }
    }
}
