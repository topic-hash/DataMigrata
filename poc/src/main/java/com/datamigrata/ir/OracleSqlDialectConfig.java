package com.datamigrata.ir;

import org.apache.calcite.jdbc.CalciteSchema;
import org.apache.calcite.schema.SchemaPlus;
import org.apache.calcite.schema.impl.AbstractTable;
import org.apache.calcite.rel.type.RelDataType;
import org.apache.calcite.rel.type.RelDataTypeFactory;
import org.apache.calcite.rel.type.RelDataTypeImpl;
import org.apache.calcite.sql.SqlDialect;
import org.apache.calcite.sql.dialect.OracleSqlDialect;
import org.apache.calcite.sql.parser.SqlParser;
import org.apache.calcite.tools.FrameworkConfig;
import org.apache.calcite.tools.Frameworks;

import java.util.Collections;

/**
 * Configuration for Calcite with Oracle SQL dialect support.
 * Provides in-memory schema and parser configuration.
 */
public class OracleSqlDialectConfig {

    /**
     * Create a SqlParser.Config configured for Oracle SQL dialect.
     */
    public static SqlParser.Config createParserConfig() {
        return SqlParser.configBuilder()
                .setCaseSensitive(false)
                .setConformance(SqlParser.Config.DEFAULT.conformance())
                .build();
    }

    /**
     * Create the root SchemaPlus with sample tables for PoC.
     * Tables are declared with types so Calcite can validate queries.
     */
    public static SchemaPlus createRootSchema() {
        SchemaPlus rootSchema = Frameworks.createRootSchema(true);

        // Register sample Oracle tables that the PoC can query
        // EMP table (classic Oracle demo)
        rootSchema.add("EMP", createEmpTable());
        // DEPT table
        rootSchema.add("DEPT", createDeptTable());
        // EMPLOYEES table (HR schema from the MSSQL deployment)
        rootSchema.add("EMPLOYEES", createEmployeesTable());
        // DEPARTMENTS table
        rootSchema.add("DEPARTMENTS", createDepartmentsTable());
        // LOGS table
        rootSchema.add("LOGS", createLogsTable());

        return rootSchema;
    }

    private static AbstractTable createEmpTable() {
        return new AbstractTable() {
            @Override
            public RelDataType getRowType(RelDataTypeFactory typeFactory) {
                return typeFactory.builder()
                        .add("EMPNO", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("ENAME", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 50))
                        .add("JOB", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 20))
                        .add("MGR", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("HIREDATE", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.DATE))
                        .add("SAL", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.DECIMAL, 10, 2))
                        .add("COMM", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.DECIMAL, 10, 2))
                        .add("DEPTNO", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .build();
            }
        };
    }

    private static AbstractTable createDeptTable() {
        return new AbstractTable() {
            @Override
            public RelDataType getRowType(RelDataTypeFactory typeFactory) {
                return typeFactory.builder()
                        .add("DEPTNO", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("DNAME", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 30))
                        .add("LOC", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 50))
                        .build();
            }
        };
    }

    private static AbstractTable createEmployeesTable() {
        return new AbstractTable() {
            @Override
            public RelDataType getRowType(RelDataTypeFactory typeFactory) {
                return typeFactory.builder()
                        .add("EMPLOYEE_ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("FIRST_NAME", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 50))
                        .add("LAST_NAME", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 50))
                        .add("EMAIL", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 100))
                        .add("PHONE", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 20))
                        .add("HIRE_DATE", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.DATE))
                        .add("JOB_ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 10))
                        .add("SALARY", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.DECIMAL, 10, 2))
                        .add("COMMISSION_PCT", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.DECIMAL, 5, 2))
                        .add("MANAGER_ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("DEPARTMENT_ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .build();
            }
        };
    }

    private static AbstractTable createDepartmentsTable() {
        return new AbstractTable() {
            @Override
            public RelDataType getRowType(RelDataTypeFactory typeFactory) {
                return typeFactory.builder()
                        .add("DEPARTMENT_ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("DEPARTMENT_NAME", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 50))
                        .add("LOCATION_ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .build();
            }
        };
    }

    private static AbstractTable createLogsTable() {
        return new AbstractTable() {
            @Override
            public RelDataType getRowType(RelDataTypeFactory typeFactory) {
                return typeFactory.builder()
                        .add("ID", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.INTEGER))
                        .add("MSG", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.VARCHAR, 500))
                        .add("LOG_DATE", typeFactory.createSqlType(org.apache.calcite.sql.type.SqlTypeName.TIMESTAMP))
                        .build();
            }
        };
    }

    /**
     * Create a Calcite FrameworkConfig for in-memory operation.
     */
    public static FrameworkConfig createFrameworkConfig(SchemaPlus rootSchema) {
        return Frameworks.newConfigBuilder()
                .parserConfig(createParserConfig())
                .defaultSchema(rootSchema)
                .build();
    }
}
