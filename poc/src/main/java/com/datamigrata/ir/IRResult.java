package com.datamigrata.ir;

import org.apache.calcite.rel.RelNode;
import org.apache.calcite.rel.type.RelDataType;

import java.util.ArrayList;
import java.util.List;

/**
 * Result of Calcite IR lowering (Phase 2).
 */
public class IRResult {
    private final boolean success;
    private final RelNode rootRel;
    private final RelDataType rowType;
    private final List<String> warnings;
    private final String errorMessage;

    public IRResult(boolean success, RelNode rootRel, RelDataType rowType,
                    List<String> warnings) {
        this.success = success;
        this.rootRel = rootRel;
        this.rowType = rowType;
        this.warnings = warnings;
        this.errorMessage = null;
    }

    private IRResult(boolean success, String errorMessage) {
        this.success = success;
        this.rootRel = null;
        this.rowType = null;
        this.warnings = new ArrayList<>();
        this.errorMessage = errorMessage;
    }

    public static IRResult failure(String error) {
        return new IRResult(false, error);
    }

    public boolean isSuccess() { return success; }
    public RelNode getRootRel() { return rootRel; }
    public RelDataType getRowType() { return rowType; }
    public List<String> getWarnings() { return warnings; }
    public String getErrorMessage() { return errorMessage; }

    @Override
    public String toString() {
        return "IRResult{success=" + success
                + (success ? ", rel=[" + (rootRel != null ? rootRel.getRelTypeName() : "null") + "]" : "")
                + (errorMessage != null ? ", error=" + errorMessage : "")
                + ", warnings=" + warnings.size()
                + "}";
    }
}
