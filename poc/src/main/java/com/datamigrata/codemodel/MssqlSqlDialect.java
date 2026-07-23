/*
 * DataMigrata — Oracle-to-MSSQL T-SQL Code Generator
 * Phase 4: Custom MSSQL SqlDialect Configuration
 *
 * Wraps Apache Calcite's built-in MssqlSqlDialect and provides
 * MSSQL-specific post-processing helpers used by TSqlGenerator.
 */
package com.datamigrata.codemodel;

import org.apache.calcite.sql.SqlDialect;

/**
 * MSSQL-specific dialect helpers for the DataMigrata code-generation layer.
 * <p>
 * Delegates to Calcite's {@code org.apache.calcite.sql.dialect.MssqlSqlDialect}
 * for core dialect behaviour (bracket quoting, OFFSET-FETCH, TOP clause)
 * and adds utility methods for runtime T-SQL post-processing that Calcite
 * does not handle out of the box.
 */
public final class MssqlSqlDialect {

    private MssqlSqlDialect() {
        // utility class — no instances
    }

    // -----------------------------------------------------------------------
    // Calcite dialect delegate
    // -----------------------------------------------------------------------

    /**
     * Returns the underlying Calcite {@link SqlDialect} configured for
     * Microsoft SQL Server.
     * <p>
     * The returned dialect:
     * <ul>
     *   <li>Quotes identifiers with {@code [brackets]}</li>
     *   <li>Uses {@code TOP N} / {@code OFFSET-FETCH} for row limiting</li>
     *   <li>Emits {@code NVARCHAR} as the preferred string type</li>
     * </ul>
     */
    public static SqlDialect getDialect() {
        return org.apache.calcite.sql.dialect.MssqlSqlDialect.DEFAULT;
    }

    // -----------------------------------------------------------------------
    // Post-processing utilities
    // -----------------------------------------------------------------------

    /**
     * Applies MSSQL-specific textual post-processing to SQL emitted by
     * Calcite's {@link SqlDialect}.
     *
     * <h3>Transformations applied (in order):</h3>
     * <ol>
     *   <li>{@code CURRENT_TIMESTAMP} → {@code GETDATE()}</li>
     *   <li>{@code FETCH FIRST} without {@code OFFSET} → {@code TOP N} (ANSI simplification)</li>
     *   <li>Removes orphaned {@code FROM [DUAL]} clauses</li>
     *   <li>Normalises whitespace</li>
     * </ol>
     *
     * @param sql raw SQL emitted by Calcite
     * @return post-processed T-SQL
     */
    public static String postProcessTSql(String sql) {
        if (sql == null || sql.isBlank()) {
            return sql;
        }

        String result = sql;

        // 1. CURRENT_TIMESTAMP → GETDATE()
        //    Calcite renders CURRENT_TIMESTAMP as-is; MSSQL idiomatic usage prefers GETDATE().
        result = replaceCurrentTimestampWithGetdate(result);

        // 2. Simplify OFFSET 0 ROWS FETCH FIRST N ROWS ONLY → TOP N
        result = simplifyOffsetFetchToTop(result);

        // 3. Remove FROM [DUAL] / FROM DUAL (Oracle artifact that leaked through)
        result = removeDualReference(result);

        // 4. Normalise whitespace
        result = result.replaceAll("\\s+", " ").trim();

        return result;
    }

    // ---- private helpers ---------------------------------------------------

    /**
     * Replaces standalone {@code CURRENT_TIMESTAMP} tokens with {@code GETDATE()}.
     * <p>
     * Uses word-boundary matching to avoid corrupting identifiers or literals
     * that happen to contain the substring "CURRENT_TIMESTAMP".
     */
    private static String replaceCurrentTimestampWithGetdate(String sql) {
        // Case-insensitive word-boundary replacement
        return sql.replaceAll(
                "(?i)\\bCURRENT_TIMESTAMP\\b",
                "GETDATE()");
    }

    /**
     * Converts {@code OFFSET 0 ROWS FETCH FIRST N ROWS ONLY} to the more
     * idiomatic MSSQL {@code TOP N} form.
     * <p>
     * Pattern examples matched:
     * <ul>
     *   <li>{@code ...OFFSET 0 ROWS FETCH FIRST 10 ROWS ONLY → ...TOP 10}</li>
     * </ul>
     * Offset values other than zero are left untouched (they require
     * OFFSET-FETCH syntax).
     */
    private static String simplifyOffsetFetchToTop(String sql) {
        // Match: OFFSET 0 ROWS FETCH FIRST <n> ROWS ONLY
        // Replace with: TOP <n>
        return sql.replaceAll(
                "(?i)\\bOFFSET\\s+0\\s+ROWS\\s+FETCH\\s+FIRST\\s+(\\d+)\\s+ROWS\\s+ONLY\\b",
                "TOP $1");
    }

    /**
     * Strips {@code FROM DUAL} / {@code FROM [DUAL]} from the SQL.
     * Oracle uses DUAL as a single-row dummy table; MSSQL does not
     * require a FROM clause for expressions.
     */
    private static String removeDualReference(String sql) {
        // Remove "FROM [DUAL]" or "FROM DUAL" including surrounding whitespace
        return sql.replaceAll(
                "(?i)\\s+FROM\\s+\\[?DUAL\\]?\\b",
                "");
    }

    // -----------------------------------------------------------------------
    // MSSQL-specific identifier helpers
    // -----------------------------------------------------------------------

    /**
     * Quotes a plain identifier with MSSQL {@code [brackets]}.
     * <p>
     * If the identifier is already bracketed, returns it unchanged.
     */
    public static String quoteIdentifier(String identifier) {
        if (identifier == null || identifier.isBlank()) {
            return identifier;
        }
        if (identifier.startsWith("[") && identifier.endsWith("]")) {
            return identifier;
        }
        return "[" + identifier + "]";
    }

    /**
     * Generates an MSSQL {@code SCOPE_IDENTITY()} expression for
     * retrieving the last-inserted identity value.
     */
    public static String scopeIdentityExpr() {
        return "SCOPE_IDENTITY()";
    }

    /**
     * Generates the MSSQL type declaration for an NVARCHAR column
     * of the given maximum length.
     */
    public static String nvarcharDeclaration(int maxLen) {
        return "NVARCHAR(" + maxLen + ")";
    }

    /**
     * Generates the MSSQL type declaration for an NVARCHAR(MAX) column.
     */
    public static String nvarcharMax() {
        return "NVARCHAR(MAX)";
    }
}
