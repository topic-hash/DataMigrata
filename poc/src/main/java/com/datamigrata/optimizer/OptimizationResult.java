package com.datamigrata.optimizer;

import org.apache.calcite.rel.RelNode;

import java.util.List;

/**
 * Result of the optimization phase (Phase 3).
 */
public class OptimizationResult {
    private final RelNode optimizedRel;
    private final List<RuleApplied> rulesApplied;
    private final boolean changed;
    private final List<String> warnings;

    public OptimizationResult(RelNode optimizedRel, List<RuleApplied> rulesApplied,
                               boolean changed, List<String> warnings) {
        this.optimizedRel = optimizedRel;
        this.rulesApplied = rulesApplied;
        this.changed = changed;
        this.warnings = warnings;
    }

    public RelNode getOptimizedRel() { return optimizedRel; }
    public List<RuleApplied> getRulesApplied() { return rulesApplied; }
    public boolean isChanged() { return changed; }
    public List<String> getWarnings() { return warnings; }

    @Override
    public String toString() {
        return "OptimizationResult{changed=" + changed
                + ", rules=" + rulesApplied.size()
                + "}";
    }
}
