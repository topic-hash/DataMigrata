package com.datamigrata.optimizer;

/**
 * Record of a single optimization rule that was applied.
 */
public class RuleApplied {
    private final String ruleName;
    private final String description;

    public RuleApplied(String ruleName, String description) {
        this.ruleName = ruleName;
        this.description = description;
    }

    public String getRuleName() { return ruleName; }
    public String getDescription() { return description; }

    @Override
    public String toString() {
        return ruleName + ": " + description;
    }
}
