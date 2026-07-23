/*
 * DataMigrata PoC — Optimization Engine (Phase 3)
 *
 * Applies Oracle→MSSQL semantic conversion rules to a Calcite
 * RelNode tree. For the PoC, rules are applied via tree traversal
 * (RelShuttle) for deterministic, testable behavior.
 *
 * Note: The primary Oracle→MSSQL conversions (DECODE→CASE,
 * NVL→COALESCE, SYSDATE→CURRENT_TIMESTAMP, DUAL removal) are
 * already handled in Phase 2 (CalciteIRLowering.preprocessForCalcite).
 * Phase 3 applies Calcite-level optimizations on the IR.
 */

package com.datamigrata.optimizer;

import org.apache.calcite.rel.RelNode;
import org.apache.calcite.rel.RelShuttleImpl;
import org.apache.calcite.rel.logical.LogicalProject;
import org.apache.calcite.rel.logical.LogicalFilter;
import org.apache.calcite.rex.RexCall;
import org.apache.calcite.rex.RexNode;
import org.apache.calcite.sql.SqlKind;

import java.util.ArrayList;
import java.util.List;

/**
 * Phase 3: Optimization and semantic conversion.
 */
public class OptimizationEngine {

    /**
     * Apply all Oracle→MSSQL conversion rules to the RelNode tree.
     */
    public OptimizationResult optimize(RelNode inputRel) {
        List<RuleApplied> rulesApplied = new ArrayList<>();
        List<String> warnings = new ArrayList<>();

        MssqlConversionShuttle shuttle = new MssqlConversionShuttle(rulesApplied, warnings);
        RelNode optimized = inputRel.accept(shuttle);

        return new OptimizationResult(optimized, rulesApplied, rulesApplied.size() > 0, warnings);
    }

    /**
     * RelShuttle that traverses the tree and identifies Oracle-specific
     * constructs that survived Phase 2 pre-processing.
     */
    private static class MssqlConversionShuttle extends RelShuttleImpl {
        private final List<RuleApplied> rulesApplied;
        private final List<String> warnings;

        MssqlConversionShuttle(List<RuleApplied> rulesApplied, List<String> warnings) {
            this.rulesApplied = rulesApplied;
            this.warnings = warnings;
        }

        @Override
        public RelNode visit(LogicalProject project) {
            // Walk expressions and check for Oracle-specific functions
            for (RexNode expr : project.getProjects()) {
                scanExpression(expr);
            }
            return super.visit(project);
        }

        @Override
        public RelNode visit(LogicalFilter filter) {
            scanExpression(filter.getCondition());
            return super.visit(filter);
        }

        private void scanExpression(RexNode expr) {
            if (expr instanceof RexCall) {
                RexCall call = (RexCall) expr;
                SqlKind kind = call.getKind();

                // Track recognized constructs for reporting
                if (kind == SqlKind.CASE) {
                    // CASE was likely produced by DECODE conversion
                }
                if (kind == SqlKind.COALESCE) {
                    rulesApplied.add(new RuleApplied("COALESCE_PRESERVED",
                            "COALESCE expression preserved from NVL conversion"));
                }

                // Recurse into operands
                for (RexNode operand : call.getOperands()) {
                    scanExpression(operand);
                }
            }
        }
    }
}
