/*
 * DataMigrata PoC — Pipeline Integration
 *
 * Wires all four phases of the compiler pipeline together:
 *   Phase 1: Oracle SQL Parsing (AST)
 *   Phase 2: Calcite IR Lowering (RelNode tree)
 *   Phase 3: Optimization (Oracle→MSSQL semantic conversion)
 *   Phase 4: T-SQL Code Generation
 *
 * This is the main entry point for the PoC.
 */

package com.datamigrata.codemodel;

import com.datamigrata.ir.CalciteIRLowering;
import com.datamigrata.ir.IRResult;
import com.datamigrata.ir.OracleSqlDialectConfig;
import com.datamigrata.optimizer.OptimizationEngine;
import com.datamigrata.optimizer.OptimizationResult;
import com.datamigrata.optimizer.RuleApplied;
import org.apache.calcite.rel.RelNode;
import org.apache.calcite.sql.SqlNode;
import org.apache.calcite.sql.parser.SqlParser;

import java.util.ArrayList;
import java.util.List;

/**
 * End-to-end Oracle→MSSQL translation pipeline.
 *
 * Accepts Oracle SQL text and produces T-SQL through the
 * four-phase compiler pipeline.
 */
public class PipelineIntegration {

    private final CalciteIRLowering irLowering;
    private final OptimizationEngine optimizer;
    private final TSqlGenerator codeGenerator;

    public PipelineIntegration() {
        this.irLowering = new CalciteIRLowering();
        this.optimizer = new OptimizationEngine();
        this.codeGenerator = new TSqlGenerator();
    }

    /**
     * Translate an Oracle SQL statement to MSSQL T-SQL.
     *
     * @param oracleSql the Oracle SQL text
     * @return PipelineResult with T-SQL output and full diagnostics
     */
    public PipelineResult translate(String oracleSql) {
        long startTime = System.currentTimeMillis();
        List<String> allErrors = new ArrayList<>();
        List<String> allWarnings = new ArrayList<>();
        List<String> rulesApplied = new ArrayList<>();

        // Phase 2: IR Lowering (includes Phase 1 pre-processing + Calcite parsing)
        IRResult irResult = irLowering.lower(oracleSql);

        if (!irResult.isSuccess()) {
            return PipelineResult.failure(oracleSql, irResult.getErrorMessage(),
                    System.currentTimeMillis() - startTime);
        }

        allWarnings.addAll(irResult.getWarnings());

        // Phase 3: Optimization / Semantic Conversion
        OptimizationResult optResult = optimizer.optimize(irResult.getRootRel());
        allWarnings.addAll(optResult.getWarnings());

        for (RuleApplied rule : optResult.getRulesApplied()) {
            rulesApplied.add(rule.getRuleName() + ": " + rule.getDescription());
        }

        RelNode optimizedRel = optResult.getOptimizedRel();

        // Phase 4: T-SQL Code Generation
        CodeGenerationResult codeResult = codeGenerator.generate(optimizedRel);

        if (!codeResult.isSuccess()) {
            allErrors.add(codeResult.getErrorMessage());
            return new PipelineResult(
                    oracleSql,
                    oracleSql,  // preprocessed = original for simplicity
                    null,
                    false,
                    allErrors,
                    allWarnings,
                    rulesApplied,
                    System.currentTimeMillis() - startTime
            );
        }

        allWarnings.addAll(codeResult.getWarnings());

        long elapsed = System.currentTimeMillis() - startTime;

        return new PipelineResult(
                oracleSql,
                oracleSql,
                codeResult.getTsql(),
                true,
                allErrors,
                allWarnings,
                rulesApplied,
                elapsed
        );
    }
}
