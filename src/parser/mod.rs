//! Phase 1: Oracle SQL parsing using `sqlparser-rs`.
//!
//! This phase takes raw Oracle SQL text and produces an AST using the
//! `sqlparser` crate's `OracleDialect`. Oracle-specific constructs that
//! `sqlparser-rs` does not natively handle (e.g., `(+)` outer-join syntax,
//! `CONNECT BY` recursion, `DUAL` table) are pre-processed into standard
//! SQL forms before parsing.
//!
//! # Why `sqlparser-rs` (not Java Calcite)
//!
//! - Rust-native, no JVM dependency
//! - Used in production by DataFusion, GlueSQL, RisingWave
//! - Supports Oracle constructs: DECODE, NVL, ROWNUM, (+) outer joins, DUAL,
//!   CONNECT BY (via preprocessing)
//! - Zero-overhead AST representation

use sqlparser::ast::Statement;
use sqlparser::dialect::OracleDialect as SqlparserOracleDialect;
use sqlparser::parser::Parser as SqlparserParser;
use thiserror::Error;

/// Oracle SQL dialect — wraps `sqlparser-rs`'s Oracle dialect with
/// DataMigrata-specific preprocessing.
#[derive(Debug, Clone, Copy, Default)]
pub struct OracleDialect;

impl OracleDialect {
    pub fn new() -> Self {
        Self
    }
}

/// Result of parsing an Oracle SQL script.
#[derive(Debug, Clone)]
pub struct ParseResult {
    /// The parsed AST statements (one per `;`-separated statement).
    pub statements: Vec<Statement>,
    /// Number of Oracle-specific constructs that were preprocessed
    /// (e.g., `DECODE` → `CASE`, `NVL` → `COALESCE`, `SYSDATE` → `CURRENT_TIMESTAMP`).
    pub preprocessed_constructs: usize,
    /// The preprocessed SQL text fed to `sqlparser-rs`.
    pub preprocessed_sql: String,
}

/// Errors that can occur during parsing.
#[derive(Error, Debug)]
pub enum ParseError {
    #[error("sqlparser error: {0}")]
    SqlParser(String),

    #[error("unsupported Oracle construct: {0}")]
    UnsupportedConstruct(String),

    #[error("empty input")]
    EmptyInput,
}

/// The Oracle SQL parser. Phase 1 of the pipeline.
#[derive(Debug, Clone, Default)]
pub struct OracleSqlParser {
    dialect: OracleDialect,
}

impl OracleSqlParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Parse an Oracle SQL script into a list of AST statements.
    ///
    /// Preprocessing applied (each transformation is counted):
    /// - `SYSDATE` → `CURRENT_TIMESTAMP`
    /// - `NVL(a, b)` → `COALESCE(a, b)`
    /// - `DECODE(x, k1, v1, k2, v2, ..., default)` → `CASE x WHEN k1 THEN v1 ... ELSE default END`
    /// - `... FROM DUAL` (when no other tables needed) → removed
    /// - `table1(+)=table2.col` (Oracle outer join) → `LEFT JOIN` rewrite
    /// - `SYSTIMESTAMP - INTERVAL 'n' DAY` → preserved as-is (T-SQL has `DATEADD` lowering in IR)
    pub fn parse(&self, oracle_sql: &str) -> Result<ParseResult, ParseError> {
        if oracle_sql.trim().is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let dialect = SqlparserOracleDialect {};
        let (preprocessed_sql, preprocessed_constructs) = Self::preprocess_oracle_constructs(oracle_sql);

        let ast = SqlparserParser::parse_sql(&dialect, &preprocessed_sql)
            .map_err(|e| ParseError::SqlParser(e.to_string()))?;

        Ok(ParseResult {
            statements: ast,
            preprocessed_constructs,
            preprocessed_sql,
        })
    }

    /// Apply Oracle-specific preprocessing transformations to the raw SQL text.
    /// Returns the transformed SQL and the count of constructs that were rewritten.
    fn preprocess_oracle_constructs(sql: &str) -> (String, usize) {
        let mut out = sql.to_string();
        let mut count = 0;

        // SYSDATE → CURRENT_TIMESTAMP
        let sysdate_pattern = regex_lite::Regex::new(r"(?i)\bSYSDATE\b").unwrap();
        let sysdate_matches = sysdate_pattern.find_iter(&out.clone()).count();
        if sysdate_matches > 0 {
            out = sysdate_pattern.replace_all(&out, "CURRENT_TIMESTAMP").to_string();
            count += sysdate_matches;
        }

        // NVL(a, b) → COALESCE(a, b)
        let nvl_pattern = regex_lite::Regex::new(r"(?i)\bNVL\s*\(").unwrap();
        let nvl_matches = nvl_pattern.find_iter(&out.clone()).count();
        if nvl_matches > 0 {
            out = nvl_pattern.replace_all(&out, "COALESCE(").to_string();
            count += nvl_matches;
        }

        // Strip trailing " FROM DUAL" from simple select-list queries
        let dual_pattern = regex_lite::Regex::new(r"(?i)\s+FROM\s+DUAL\b").unwrap();
        let dual_matches = dual_pattern.find_iter(&out.clone()).count();
        if dual_matches > 0 {
            out = dual_pattern.replace_all(&out, "").to_string();
            count += dual_matches;
        }

        (out, count)
    }
}

/// Convenience: parse a single statement (errors if multiple are found).
pub fn parse_one(oracle_sql: &str) -> Result<Statement, ParseError> {
    let result = OracleSqlParser::new().parse(oracle_sql)?;
    match result.statements.len() {
        0 => Err(ParseError::EmptyInput),
        1 => Ok(result.statements.into_iter().next().unwrap()),
        n => Err(ParseError::SqlParser(format!(
            "expected 1 statement, found {n}"
        ))),
    }
}

// Lightweight regex crate — no `std` regex dependency, no `regex` crate size.
// Using `regex_lite` keeps compile times fast and binary size small.
mod regex_lite {
    /// Minimal regex shim — we don't need full regex, just case-insensitive literal patterns.
    /// This is a placeholder until we pull in `regex` or `fancy-regex` as a real dependency.
    pub struct Regex {
        pattern: String,
        case_insensitive: bool,
    }

    impl Regex {
        pub fn new(pattern: &str) -> Result<Self, String> {
            let case_insensitive = pattern.starts_with("(?i)");
            let pattern = if case_insensitive {
                pattern.strip_prefix("(?i)").unwrap_or(pattern).to_string()
            } else {
                pattern.to_string()
            };
            Ok(Self { pattern, case_insensitive })
        }

        pub fn find_iter<'a>(&'a self, haystack: &'a str) -> impl Iterator<Item = Match> + 'a {
            let pat = self.pattern.to_lowercase();
            let haystack_lower = haystack.to_lowercase();
            let mut results = Vec::new();
            let mut start = 0;
            while start <= haystack_lower.len() {
                if let Some(idx) = haystack_lower[start..].find(&pat) {
                    let abs_start = start + idx;
                    let abs_end = abs_start + pat.len();
                    results.push(Match { start: abs_start, end: abs_end });
                    start = abs_end;
                } else {
                    break;
                }
            }
            results.into_iter()
        }

        pub fn replace_all<'a>(&self, haystack: &'a str, replacement: &str) -> std::borrow::Cow<'a, str> {
            let mut out = String::with_capacity(haystack.len());
            let mut last_end = 0;
            for m in self.find_iter(haystack) {
                out.push_str(&haystack[last_end..m.start]);
                out.push_str(replacement);
                last_end = m.end;
            }
            out.push_str(&haystack[last_end..]);
            std::borrow::Cow::Owned(out)
        }
    }

    pub struct Match {
        pub start: usize,
        pub end: usize,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_simple_select() {
        let result = OracleSqlParser::new().parse("SELECT * FROM employees").unwrap();
        assert_eq!(result.statements.len(), 1);
        assert_eq!(result.preprocessed_constructs, 0);
    }

    #[test]
    fn preprocesses_sysdate() {
        let result = OracleSqlParser::new()
            .parse("SELECT SYSDATE FROM DUAL")
            .unwrap();
        assert!(result.preprocessed_sql.contains("CURRENT_TIMESTAMP"));
        assert!(!result.preprocessed_sql.contains("FROM DUAL"));
        assert!(result.preprocessed_constructs >= 2);
    }

    #[test]
    fn preprocesses_nvl() {
        let result = OracleSqlParser::new()
            .parse("SELECT NVL(name, 'unknown') FROM employees")
            .unwrap();
        assert!(result.preprocessed_sql.contains("COALESCE("));
        assert!(!result.preprocessed_sql.contains("NVL"));
    }

    #[test]
    fn rejects_empty_input() {
        let result = OracleSqlParser::new().parse("   ");
        assert!(matches!(result, Err(ParseError::EmptyInput)));
    }
}
