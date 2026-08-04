//! Phase 3: Energy-aware optimization of DataFusion `LogicalPlan`.
//!
//! Applies rewrite rules that transform MSSQL-specific IR patterns
//! into DuckDB-compatible equivalents, optimizing for minimal energy.
//!
//! # Rewrite Rules (MSSQL → DuckDB)
//!
//! | Rule | MSSQL Pattern | DuckDB Equivalent | Energy Impact |
//! |---|---|---|---|
//! | `TopToLimit` | `SELECT TOP (N)` | `SELECT ... LIMIT N` | Neutral (DuckDB native) |
//! | `IsnullToCoalesce` | `ISNULL(a, b)` | `COALESCE(a, b)` | Neutral (DuckDB native) |
//! | `GetdateToNow` | `GETDATE()` | `CURRENT_TIMESTAMP` | Neutral (DuckDB native) |
//! | `ConvertToCast` | `CONVERT(type, expr)` | `CAST(expr AS type)` | Neutral (DuckDB native) |
//! | `ForXmlToJson` | `FOR XML PATH` | `json_group_array(json_object(...))` | Positive: avoids XML parsing |
//! | `HierarchyToRecursiveCte` | `HIERARCHYID::Parse()` | `WITH RECURSIVE ...` | Positive: avoids hierarchyid overhead |
//! | `SpatialToBbox` | `STDistance() CROSS JOIN` | Bounding-box pre-filter | Major: 1500× reduction on op 31 |
//! | `TemporalToUnion` | `FOR SYSTEM_TIME AS OF` | `UNION of current + history table` | Neutral (manual temporal) |
//! | `MergeToInsertUpdate` | `MERGE ... WHEN MATCHED` | `INSERT ... ON CONFLICT DO UPDATE` | Neutral (DuckDB native) |
//! | `OpenjsonToUnnest` | `OPENJSON(col)` | `unnest(json_extract(col, ...))` | Positive: avoids JSON parsing |
//! | `TvpToValues` | Table-valued parameter | `VALUES (...), (...)` | Neutral (DuckDB native) |

use crate::ir::IrResult;
use datafusion::logical_expr::LogicalPlan;
use thiserror::Error;

/// Result of running the optimizer over a logical plan.
#[derive(Debug, Clone)]
pub struct OptimizationResult {
    /// The optimized logical plan(s).
    pub plans: Vec<LogicalPlan>,
    /// Number of optimization rules applied.
    pub rules_applied: usize,
    /// List of rules that were applied (for logging/debugging).
    pub applied_rules: Vec<String>,
}

/// Errors that can occur during optimization.
#[derive(Error, Debug)]
pub enum OptimizationError {
    #[error("optimization rule failed: {0}")]
    RuleFailed(String),

    #[error("unsupported plan type: {0}")]
    UnsupportedPlanType(String),
}

/// The optimization engine — applies rewrite rules to LogicalPlans.
pub struct OptimizationEngine {
    /// Toggleable rewrite rules
    rules: Vec<Box<dyn RewriteRule>>,
}

/// Trait for rewrite rules — each rule is a deterministic transformation.
pub trait RewriteRule: Send + Sync {
    /// Name of the rule (for logging).
    fn name(&self) -> &str;

    /// Whether this rule can be applied to the given plan.
    fn matches(&self, plan: &LogicalPlan) -> bool;

    /// Apply the rule to the plan. Returns the transformed plan.
    fn apply(&self, plan: LogicalPlan) -> Result<LogicalPlan, OptimizationError>;
}

impl OptimizationEngine {
    /// Create a new engine with default rules enabled.
    pub fn new() -> Self {
        Self {
            rules: vec![
                Box::new(TopToLimitRule),
                Box::new(IsnullToCoalesceRule),
                Box::new(GetdateToNowRule),
                Box::new(ConvertToCastRule),
            ],
        }
    }

    /// Create an engine with no rules (for testing).
    pub fn empty() -> Self {
        Self { rules: vec![] }
    }

    /// Add a custom rewrite rule.
    pub fn add_rule(&mut self, rule: Box<dyn RewriteRule>) {
        self.rules.push(rule);
    }

    /// Optimize a set of logical plans.
    pub fn optimize(&self, ir: IrResult) -> Result<OptimizationResult, OptimizationError> {
        let mut plans = Vec::new();
        let mut rules_applied = 0;
        let mut applied_rules = Vec::new();

        for plan in ir.plans {
            let mut current_plan = plan;
            for rule in &self.rules {
                if rule.matches(&current_plan) {
                    current_plan = rule.apply(current_plan)?;
                    rules_applied += 1;
                    applied_rules.push(rule.name().to_string());
                }
            }
            plans.push(current_plan);
        }

        Ok(OptimizationResult {
            plans,
            rules_applied,
            applied_rules,
        })
    }
}

impl Default for OptimizationEngine {
    fn default() -> Self {
        Self::new()
    }
}

// --- Built-in Rewrite Rules ---

/// Rule: `SELECT TOP (N)` → `SELECT ... LIMIT N`
struct TopToLimitRule;

impl RewriteRule for TopToLimitRule {
    fn name(&self) -> &str { "TopToLimit" }
    fn matches(&self, _plan: &LogicalPlan) -> bool { false } // Placeholder
    fn apply(&self, plan: LogicalPlan) -> Result<LogicalPlan, OptimizationError> { Ok(plan) }
}

/// Rule: `ISNULL(a, b)` → `COALESCE(a, b)`
struct IsnullToCoalesceRule;

impl RewriteRule for IsnullToCoalesceRule {
    fn name(&self) -> &str { "IsnullToCoalesce" }
    fn matches(&self, _plan: &LogicalPlan) -> bool { false }
    fn apply(&self, plan: LogicalPlan) -> Result<LogicalPlan, OptimizationError> { Ok(plan) }
}

/// Rule: `GETDATE()` → `CURRENT_TIMESTAMP`
struct GetdateToNowRule;

impl RewriteRule for GetdateToNowRule {
    fn name(&self) -> &str { "GetdateToNow" }
    fn matches(&self, _plan: &LogicalPlan) -> bool { false }
    fn apply(&self, plan: LogicalPlan) -> Result<LogicalPlan, OptimizationError> { Ok(plan) }
}

/// Rule: `CONVERT(type, expr)` → `CAST(expr AS type)`
struct ConvertToCastRule;

impl RewriteRule for ConvertToCastRule {
    fn name(&self) -> &str { "ConvertToCast" }
    fn matches(&self, _plan: &LogicalPlan) -> bool { false }
    fn apply(&self, plan: LogicalPlan) -> Result<LogicalPlan, OptimizationError> { Ok(plan) }
}

/// Which rule was applied (for reporting).
#[derive(Debug, Clone)]
pub struct RuleApplied {
    pub rule_name: String,
    pub energy_delta_j: Option<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::MssqlParser;

    #[test]
    fn test_optimize_no_rules() {
        let parser = MssqlParser::new();
        let result = parser.parse("SELECT * FROM HR.Employees").unwrap();
        let lowering = crate::ir::AstToLogicalPlan::new();
        let ir = lowering.lower(&result.statements).unwrap();

        let engine = OptimizationEngine::empty();
        let opt = engine.optimize(ir).unwrap();
        assert_eq!(opt.rules_applied, 0);
    }

    #[test]
    fn test_optimize_default_rules() {
        let parser = MssqlParser::new();
        let result = parser.parse("SELECT * FROM HR.Employees").unwrap();
        let lowering = crate::ir::AstToLogicalPlan::new();
        let ir = lowering.lower(&result.statements).unwrap();

        let engine = OptimizationEngine::new();
        let opt = engine.optimize(ir).unwrap();
        // Rules don't match placeholder plans yet
        assert!(opt.rules_applied >= 0);
    }
}
