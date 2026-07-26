//! Phase 3: DataFusion `LogicalPlan` optimization.
//!
//! Applies rule-based optimizations to the lowered `LogicalPlan`. Uses
//! DataFusion's optimizer framework, which provides a Rust-native equivalent
//! of Calcite's `RelOptRule` system.
//!
//! # Built-in DataFusion Rules Used
//!
//! - `EliminateProjection` — removes no-op projections
//! - `SimplifyExpressions` — constant folding, expression simplification
//! - `PushDownProjection` — pushes projections to scan nodes
//! - `PushDownFilter` — pushes predicates to scan nodes
//! - `SingleDistinctToGroupBy` — rewrites `COUNT(DISTINCT x)` to `COUNT(x) GROUP BY`
//!
//! # Custom Oracle→MSSQL Optimization Rules
//!
//! - `MssqlFunctionConversion` — rewrites Oracle functions to MSSQL equivalents
//!   (e.g., `SYSDATE` → `GETDATE()`, `SYSTIMESTAMP` → `SYSUTCDATETIME()`,
//!   `TO_DATE(x)` → `CAST(x AS DATETIME)`)
//! - `DateArithmeticRewrite` — `date_col + INTERVAL 'n' DAY` → `DATEADD(DAY, n, date_col)`
//! - `HierarchicalQueryRewrite` — `CONNECT BY` → recursive CTE + `HIERARCHYID`
//! - `FlashbackQueryRewrite` — `AS OF TIMESTAMP` → `FOR SYSTEM_TIME AS OF`

use crate::ir::IrResult;
use datafusion::logical_expr::LogicalPlan;
use thiserror::Error;

/// Result of running the optimizer over a logical plan.
#[derive(Debug, Clone)]
pub struct OptimizationResult {
    /// Optimized plans, one per input plan.
    pub plans: Vec<LogicalPlan>,
    /// The list of optimization rules that were applied (in order).
    pub rules_applied: Vec<RuleApplied>,
}

/// A rule that was applied during optimization.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleApplied {
    EliminateProjection,
    SimplifyExpressions,
    PushDownProjection,
    PushDownFilter,
    MssqlFunctionConversion,
    DateArithmeticRewrite,
    HierarchicalQueryRewrite,
    FlashbackQueryRewrite,
}

impl RuleApplied {
    pub fn name(&self) -> &'static str {
        match self {
            Self::EliminateProjection => "EliminateProjection",
            Self::SimplifyExpressions => "SimplifyExpressions",
            Self::PushDownProjection => "PushDownProjection",
            Self::PushDownFilter => "PushDownFilter",
            Self::MssqlFunctionConversion => "MssqlFunctionConversion",
            Self::DateArithmeticRewrite => "DateArithmeticRewrite",
            Self::HierarchicalQueryRewrite => "HierarchicalQueryRewrite",
            Self::FlashbackQueryRewrite => "FlashbackQueryRewrite",
        }
    }
}

/// Errors that can occur during optimization.
#[derive(Error, Debug)]
pub enum OptimizationError {
    #[error("optimization rule {rule} failed: {message}")]
    RuleFailed { rule: String, message: String },

    #[error("no plans to optimize")]
    NoPlans,
}

/// The optimization engine. Phase 3 of the pipeline.
#[derive(Debug, Clone, Default)]
pub struct OptimizationEngine {
    rules: Vec<RuleApplied>,
}

impl OptimizationEngine {
    pub fn new() -> Self {
        // Default rule set — applied in this order
        let rules = vec![
            RuleApplied::MssqlFunctionConversion,
            RuleApplied::DateArithmeticRewrite,
            RuleApplied::HierarchicalQueryRewrite,
            RuleApplied::FlashbackQueryRewrite,
            RuleApplied::SimplifyExpressions,
            RuleApplied::EliminateProjection,
            RuleApplied::PushDownProjection,
            RuleApplied::PushDownFilter,
        ];
        Self { rules }
    }

    /// Optimize a list of logical plans.
    ///
    /// Stub: real implementation constructs a DataFusion `Optimizer` with the
    /// built-in rules plus custom Oracle→MSSQL rules, and calls
    /// `optimizer.optimize(plan, &config, |_, _| None)`.
    pub fn optimize(&self, ir: IrResult) -> Result<OptimizationResult, OptimizationError> {
        if ir.plans.is_empty() {
            // No plans = no work — return empty result. This is not an error
            // because the scaffolding IR lowering phase returns no plans yet.
            return Ok(OptimizationResult {
                plans: Vec::new(),
                rules_applied: Vec::new(),
            });
        }

        let mut applied = Vec::new();
        for rule in &self.rules {
            // Real implementation: try to apply each rule to each plan.
            // If the rule changes the plan, record it in `applied`.
            let _ = rule;
            applied.push(RuleApplied::MssqlFunctionConversion);
        }

        Ok(OptimizationResult {
            plans: ir.plans.clone(),
            rules_applied: applied,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ir::IrResult;

    #[test]
    fn empty_plans_yield_empty_result() {
        let ir = IrResult { plans: vec![], lowered_constructs: 0 };
        let result = OptimizationEngine::new().optimize(ir).unwrap();
        assert!(result.plans.is_empty());
        assert!(result.rules_applied.is_empty());
    }
}
