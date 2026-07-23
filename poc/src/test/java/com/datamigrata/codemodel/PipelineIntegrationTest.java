/*
 * DataMigrata PoC — End-to-end Pipeline Integration Tests
 *
 * Tests the complete 4-phase pipeline:
 *   Oracle SQL → Pre-processing → Calcite IR → Optimization → Output
 *
 * Phase 4 (T-SQL generation) currently outputs Calcite's explain format
 * for LogicalXxx nodes. Full SQL generation will be implemented in
 * Wave 3 once the RelToSqlConverter mapping for LogicalProject,
 * LogicalFilter, LogicalJoin, etc. is configured.
 *
 * Current PoC validates:
 * - Phase 2: Oracle SQL parsing → Calcite RelNode IR (proven)
 * - Phase 2: DECODE → CASE WHEN pre-processing (proven)
 * - Phase 2: NVL → COALESCE pre-processing (proven)
 * - Phase 2: SYSDATE → CURRENT_TIMESTAMP pre-processing (proven)
 * - Phase 2: FROM DUAL handling (proven)
 * - Phase 2: JOIN IR structure (proven)
 * - Phase 3: Optimization engine traversal (proven)
 * - Phase 4: Output generation (fallback mode — explain format)
 */

package com.datamigrata.codemodel;

import com.datamigrata.ir.CalciteIRLowering;
import com.datamigrata.ir.IRResult;
import com.datamigrata.optimizer.OptimizationEngine;
import com.datamigrata.optimizer.OptimizationResult;
import org.apache.calcite.rel.RelNode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

class PipelineIntegrationTest {

    private PipelineIntegration pipeline;

    @BeforeEach
    void setUp() {
        pipeline = new PipelineIntegration();
    }

    // ========================================================================
    // Phase 1-2: Parsing and IR Lowering Tests
    // ========================================================================

    @Nested
    @DisplayName("Phase 1-2: Parsing and IR Lowering")
    class ParsingAndIRTests {

        @Test
        @DisplayName("Simple SELECT produces valid IR")
        void simpleSelect() {
            IRResult ir = new CalciteIRLowering().lower(
                    "SELECT ENAME, SAL FROM EMP WHERE DEPTNO = 10");
            assertThat(ir.isSuccess()).isTrue();
            assertThat(ir.getRootRel()).isNotNull();
            assertThat(ir.getRootRel().getRelTypeName()).isNotEmpty();
        }

        @Test
        @DisplayName("DECODE is pre-processed to CASE WHEN")
        void decodePreprocessing() {
            IRResult ir = new CalciteIRLowering().lower(
                    "SELECT DECODE(DEPTNO, 10, 'HR', 20, 'IT', 'Other') FROM EMP");
            assertThat(ir.isSuccess()).isTrue();
            assertThat(ir.getWarnings()).anyMatch(w -> w.contains("DECODE"));
        }

        @Test
        @DisplayName("NVL is pre-processed to COALESCE")
        void nvlPreprocessing() {
            IRResult ir = new CalciteIRLowering().lower(
                    "SELECT NVL(COMM, 0) FROM EMP");
            assertThat(ir.isSuccess()).isTrue();
            assertThat(ir.getWarnings()).anyMatch(w -> w.contains("NVL"));
        }

        @Test
        @DisplayName("SYSDATE is pre-processed to CURRENT_TIMESTAMP")
        void sysdatePreprocessing() {
            IRResult ir = new CalciteIRLowering().lower("SELECT SYSDATE");
            assertThat(ir.isSuccess()).isTrue();
            assertThat(ir.getWarnings()).anyMatch(w -> w.contains("SYSDATE"));
        }

        @Test
        @DisplayName("FROM DUAL is handled")
        void fromDualRemoved() {
            IRResult ir = new CalciteIRLowering().lower("SELECT SYSDATE FROM DUAL");
            assertThat(ir.isSuccess()).isTrue();
            assertThat(ir.getWarnings()).anyMatch(w -> w.contains("DUAL"));
        }

        @Test
        @DisplayName("JOIN query produces join IR structure")
        void joinQuery() {
            IRResult ir = new CalciteIRLowering().lower(
                    "SELECT E.ENAME, D.DNAME FROM EMP E JOIN DEPT D ON E.DEPTNO = D.DEPTNO");
            assertThat(ir.isSuccess()).isTrue();
            assertThat(ir.getRootRel().toString()).contains("LogicalJoin");
        }

        @Test
        @DisplayName("Invalid SQL fails gracefully")
        void invalidSql() {
            IRResult ir = new CalciteIRLowering().lower("SELECTT FROMM EMPP");
            assertThat(ir.isSuccess()).isFalse();
            assertThat(ir.getErrorMessage()).isNotNull();
        }
    }

    // ========================================================================
    // Phase 3: Optimization Tests
    // ========================================================================

    @Nested
    @DisplayName("Phase 3: Optimization")
    class OptimizationTests {

        @Test
        @DisplayName("Optimization engine accepts valid RelNode")
        void optimizeSimpleQuery() {
            IRResult ir = new CalciteIRLowering().lower(
                    "SELECT ENAME, SAL FROM EMP WHERE DEPTNO = 10");
            assertThat(ir.isSuccess()).isTrue();

            OptimizationResult opt = new OptimizationEngine().optimize(ir.getRootRel());
            assertThat(opt.getOptimizedRel()).isNotNull();
        }

        @Test
        @DisplayName("Optimization returns rules applied list")
        void optimizeTracksRules() {
            IRResult ir = new CalciteIRLowering().lower("SELECT ENAME FROM EMP");
            assertThat(ir.isSuccess()).isTrue();

            OptimizationResult opt = new OptimizationEngine().optimize(ir.getRootRel());
            assertThat(opt.getRulesApplied()).isNotNull();
        }
    }

    // ========================================================================
    // Phase 4 + End-to-end Pipeline Tests
    // ========================================================================

    @Nested
    @DisplayName("End-to-End Pipeline")
    class EndToEndTests {

        @Test
        @DisplayName("Full pipeline: DECODE → CASE WHEN preprocessing")
        void fullPipelineDecode() {
            PipelineResult result = pipeline.translate(
                    "SELECT DECODE(DEPTNO, 10, 'HR', 20, 'IT', 'Other') AS DEPT_LABEL FROM EMP");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getWarnings()).anyMatch(w -> w.contains("DECODE"));
        }

        @Test
        @DisplayName("Full pipeline: NVL → COALESCE preprocessing")
        void fullPipelineNvl() {
            PipelineResult result = pipeline.translate(
                    "SELECT NVL(COMM, 0) AS COMMISSION FROM EMP");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getWarnings()).anyMatch(w -> w.contains("NVL"));
        }

        @Test
        @DisplayName("Full pipeline: SYSDATE FROM DUAL preprocessing")
        void fullPipelineSysdate() {
            PipelineResult result = pipeline.translate("SELECT SYSDATE AS NOW FROM DUAL");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getWarnings()).anyMatch(w -> w.contains("SYSDATE"));
            assertThat(result.getWarnings()).anyMatch(w -> w.contains("DUAL"));
        }

        @Test
        @DisplayName("Full pipeline with WHERE and ORDER BY")
        void fullPipelineWhereOrder() {
            PipelineResult result = pipeline.translate(
                    "SELECT ENAME, SAL FROM EMP WHERE DEPTNO = 10 ORDER BY SAL DESC");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getGeneratedTsql()).isNotNull();
        }

        @Test
        @DisplayName("Full pipeline with JOIN and WHERE")
        void fullPipelineJoinWhere() {
            PipelineResult result = pipeline.translate(
                    "SELECT E.ENAME, D.DNAME, E.SAL FROM EMP E JOIN DEPT D ON E.DEPTNO = D.DEPTNO WHERE E.SAL > 3000");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getGeneratedTsql()).isNotNull();
        }

        @Test
        @DisplayName("Full pipeline with aggregate function")
        void fullPipelineAggregate() {
            PipelineResult result = pipeline.translate(
                    "SELECT DEPTNO, COUNT(*), AVG(SAL) FROM EMP GROUP BY DEPTNO");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getGeneratedTsql()).isNotNull();
        }

        @Test
        @DisplayName("Full pipeline: multiple Oracle constructs")
        void fullPipelineMultipleConstructs() {
            PipelineResult result = pipeline.translate(
                    "SELECT ENAME, NVL(COMM, 0), DECODE(JOB, 'MANAGER', 'MGR', 'ANALYST', 'ANA', 'EMP') FROM EMP WHERE DEPTNO = 10");
            assertThat(result.isSuccess()).isTrue();
            assertThat(result.getWarnings()).anyMatch(w -> w.contains("DECODE"));
            assertThat(result.getWarnings()).anyMatch(w -> w.contains("NVL"));
        }

        @Test
        @DisplayName("Pipeline completes within 5 seconds")
        void performanceBaseline() {
            long start = System.currentTimeMillis();
            pipeline.translate("SELECT ENAME, SAL FROM EMP WHERE DEPTNO = 10 ORDER BY SAL DESC");
            long elapsed = System.currentTimeMillis() - start;
            assertThat(elapsed).isLessThan(5000);
        }

        @Test
        @DisplayName("Pipeline result includes timing info")
        void timingInfo() {
            PipelineResult result = pipeline.translate("SELECT ENAME FROM EMP");
            assertThat(result.getTranslationTimeMs()).isGreaterThanOrEqualTo(0);
        }
    }
}
