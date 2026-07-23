/*
 * DataMigrata PoC — Calcite IR Lowering (Phase 2)
 *
 * Converts Oracle SQL text to Calcite RelNode IR using
 * Calcite's Frameworks API (handles parser → validator → converter).
 * No external database required — in-memory schema only.
 */

package com.datamigrata.ir;

import org.apache.calcite.plan.RelOptUtil;
import org.apache.calcite.rel.RelNode;
import org.apache.calcite.rel.RelRoot;
import org.apache.calcite.schema.SchemaPlus;
import org.apache.calcite.sql.SqlNode;
import org.apache.calcite.sql.parser.SqlParser;
import org.apache.calcite.tools.FrameworkConfig;
import org.apache.calcite.tools.Frameworks;
import org.apache.calcite.tools.Planner;
import org.apache.calcite.tools.RelConversionException;
import org.apache.calcite.tools.ValidationException;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Phase 2: Lowers Oracle SQL to Calcite RelNode IR.
 *
 * Uses Calcite's Frameworks API which handles parsing, validation,
 * and conversion to RelNode in a single call.
 */
public class CalciteIRLowering {

    private final SchemaPlus rootSchema;
    private final FrameworkConfig frameworkConfig;

    public CalciteIRLowering() {
        this.rootSchema = OracleSqlDialectConfig.createRootSchema();
        this.frameworkConfig = OracleSqlDialectConfig.createFrameworkConfig(rootSchema);
    }

    /**
     * Convert Oracle SQL text to RelNode IR.
     * Handles pre-processing and IR conversion.
     *
     * @param oracleSql Oracle SQL text
     * @return IRResult with the RelNode tree
     */
    public IRResult lower(String oracleSql) {
        List<String> warnings = new ArrayList<>();

        // Pre-process Oracle-specific syntax
        String preprocessed = preprocessForCalcite(oracleSql, warnings);

        // Use Calcite Frameworks to parse, validate, and convert
        try (Planner planner = Frameworks.getPlanner(frameworkConfig)) {
            SqlNode sqlNode = planner.parse(preprocessed);
            SqlNode validated = planner.validate(sqlNode);
            RelRoot relRoot = planner.rel(validated);
            RelNode rootRel = relRoot.rel;

            return new IRResult(true, rootRel, rootRel.getRowType(), warnings);
        } catch (org.apache.calcite.sql.parser.SqlParseException e) {
            return IRResult.failure("Parse error: " + e.getMessage());
        } catch (ValidationException e) {
            return IRResult.failure("Validation error: " + e.getMessage());
        } catch (RelConversionException e) {
            return IRResult.failure("Rel conversion error: " + e.getMessage());
        } catch (Exception e) {
            return IRResult.failure("Error: " + e.getMessage());
        }
    }

    /**
     * Pre-process Oracle SQL constructs that Calcite doesn't handle natively.
     */
    private String preprocessForCalcite(String sql, List<String> warnings) {
        String result = sql.trim();
        result = convertDecodeToCase(result, warnings);
        result = convertNvlToCoalesce(result, warnings);
        result = convertSysdate(result, warnings);
        result = removeFromDual(result, warnings);
        return result;
    }

    /**
     * Convert DECODE(expr, s1, r1, s2, r2, default) → CASE WHEN.
     */
    private String convertDecodeToCase(String sql, List<String> warnings) {
        // 2-pair DECODE
        Pattern p = Pattern.compile(
                "DECODE\\s*\\(([^,]+),\\s*([^,]+),\\s*([^,]+),\\s*([^,]+),\\s*([^,]+),\\s*([^)]+)\\)",
                Pattern.CASE_INSENSITIVE
        );
        Matcher m = p.matcher(sql);
        if (m.find()) {
            String expr = m.group(1).trim();
            String s1 = m.group(2).trim(), r1 = m.group(3).trim();
            String s2 = m.group(4).trim(), r2 = m.group(5).trim();
            String def = m.group(6).trim();
            String caseExpr = "CASE WHEN " + expr + " = " + s1 + " THEN " + r1
                    + " WHEN " + expr + " = " + s2 + " THEN " + r2
                    + " ELSE " + def + " END";
            String result = sql.substring(0, m.start()) + caseExpr + sql.substring(m.end());
            warnings.add("DECODE converted to CASE WHEN (2 pairs)");
            return result;
        }
        // 1-pair DECODE
        Pattern p1 = Pattern.compile(
                "DECODE\\s*\\(([^,]+),\\s*([^,]+),\\s*([^,]+),\\s*([^)]+)\\)",
                Pattern.CASE_INSENSITIVE
        );
        m = p1.matcher(sql);
        if (m.find()) {
            String expr = m.group(1).trim();
            String s1 = m.group(2).trim(), r1 = m.group(3).trim();
            String def = m.group(4).trim();
            String caseExpr = "CASE WHEN " + expr + " = " + s1 + " THEN " + r1
                    + " ELSE " + def + " END";
            String result = sql.substring(0, m.start()) + caseExpr + sql.substring(m.end());
            warnings.add("DECODE converted to CASE WHEN (1 pair)");
            return result;
        }
        return sql;
    }

    /** NVL → COALESCE */
    private String convertNvlToCoalesce(String sql, List<String> warnings) {
        Pattern p = Pattern.compile("\\bNVL\\s*\\(([^,]+),\\s*([^)]+)\\)", Pattern.CASE_INSENSITIVE);
        Matcher m = p.matcher(sql);
        if (m.find()) {
            String coalesce = "COALESCE(" + m.group(1).trim() + ", " + m.group(2).trim() + ")";
            String result = sql.substring(0, m.start()) + coalesce + sql.substring(m.end());
            warnings.add("NVL converted to COALESCE");
            return result;
        }
        return sql;
    }

    /** SYSDATE → CURRENT_TIMESTAMP */
    private String convertSysdate(String sql, List<String> warnings) {
        if (sql.toUpperCase().contains("SYSDATE")) {
            warnings.add("SYSDATE converted to CURRENT_TIMESTAMP");
            return sql.replaceAll("\\bSYSDATE\\b", "CURRENT_TIMESTAMP");
        }
        return sql;
    }

    /** FROM DUAL removal — actually remove it before Calcite parsing */
    private String removeFromDual(String sql, List<String> warnings) {
        Pattern p = Pattern.compile("\\bFROM\\s+DUAL\\b", Pattern.CASE_INSENSITIVE);
        Matcher m = p.matcher(sql);
        if (m.find()) {
            String result = sql.substring(0, m.start()) + sql.substring(m.end());
            warnings.add("FROM DUAL removed");
            return result;
        }
        return sql;
    }
}
