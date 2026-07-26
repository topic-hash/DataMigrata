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

        // SYSDATE → CURRENT_TIMESTAMP  (whole-word, case-insensitive)
        out = Self::rewrite_keyword_whole_word(&out, "SYSDATE", "CURRENT_TIMESTAMP", &mut count);

        // NVL( → COALESCE(  (keyword followed by '(')
        out = Self::rewrite_keyword_with_paren(&out, "NVL", "COALESCE", &mut count);

        // Strip trailing " FROM DUAL" from simple select-list queries
        out = Self::strip_from_dual(&out, &mut count);

        // Detect CONNECT BY — sqlparser-rs does parse it, but we count it as
        // an Oracle-specific construct so the optimizer knows to apply the
        // HierarchicalQueryRewrite rule.
        Self::count_keyword(&out, "CONNECT BY", &mut count);
        Self::count_keyword(&out, "START WITH", &mut count);
        Self::count_keyword(&out, "CONNECT_BY_ROOT", &mut count);
        Self::count_keyword(&out, "SYS_CONNECT_BY_PATH", &mut count);

        // Oracle PL/SQL programmability constructs that sqlparser-rs does not
        // recognise. Each is stripped from the SQL fed to `sqlparser-rs` and
        // preserved as a `/* ... */` comment so downstream phases can recover
        // the original semantics if needed.
        //
        // `regex_lite` is a literal-substring shim and cannot express the
        // identifier-extraction these rules require, so they use small
        // case-insensitive byte-level helpers below.
        //
        //   BULK COLLECT INTO <var>            → /* BULK_COLLECT_INTO: <var> */
        //   FORALL <range> <DML>               → /* FORALL: <range> */ <DML>
        //   ... RETURNING <col> INTO :<var>    → ... RETURNING <col> /* RETURNING_INTO: :<var> */
        out = Self::preprocess_bulk_collect_into(out, &mut count);
        out = Self::preprocess_forall(out, &mut count);
        out = Self::preprocess_returning_into(out, &mut count);

        // Oracle XML functions — `sqlparser-rs` does not recognise
        // `XMLEXISTS`, `XMLQUERY`, or `XMLSERIALIZE`, so rewrite them into
        // MSSQL-compatible forms before parsing:
        //   XMLEXISTS('/path' PASSING col)               → (col.exist('/path') = 1)
        //   XMLQUERY('/path' PASSING col RETURNING ...)  → col.query('/path')
        //   XMLSERIALIZE(DOCUMENT col AS <type>)         → CAST(col AS NVARCHAR(MAX))
        out = Self::rewrite_xml_functions(out, &mut count);

        // Oracle VIEW clauses that sqlparser-rs does not recognise.
        //
        //   CREATE OR REPLACE FORCE VIEW  → CREATE OR REPLACE /* FORCE_VIEW */ VIEW
        //   ... WITH CHECK OPTION            → ... /* WITH_CHECK_OPTION */
        //   ... WITH READ ONLY               → ... /* WITH_READ_ONLY */
        out = Self::preprocess_view_clauses(out, &mut count);

        // Oracle ORDER SIBLINGS BY — sqlparser-rs does not recognise SIBLINGS.
        //   ORDER SIBLINGS BY col  →  ORDER BY col /* SIBLINGS */
        out = Self::preprocess_order_siblings_by(out, &mut count);

        // Oracle Flashback (temporal) clauses — `sqlparser-rs` does not
        // recognise `AS OF TIMESTAMP (expr)`, `AS OF SCN <n>`, or
        // `VERSIONS BETWEEN TIMESTAMP <e1> AND <e2>`. Strip the clause and
        // preserve it in a comment so the surrounding SELECT parses and
        // downstream phases can recover the temporal semantics.
        //
        //   AS OF TIMESTAMP (expr)             → /* FLASHBACK_AS_OF: expr */
        //   AS OF SCN <n>                      → /* FLASHBACK_AS_OF_SCN: <n> */
        //   VERSIONS BETWEEN TIMESTAMP <e1> AND <e2>
        //                                       → /* FLASHBACK_VERSIONS_BETWEEN: <e1> AND <e2> */
        out = Self::rewrite_flashback(out, &mut count);

        (out, count)
    }

    /// Strip `BULK COLLECT INTO <var>` and preserve it as a comment so the
    /// surrounding `SELECT ... FROM ...` parses with `sqlparser-rs`.
    ///
    /// Example: `SELECT * BULK COLLECT INTO v FROM t`
    ///       → `SELECT * /* BULK_COLLECT_INTO: v */ FROM t`
    fn preprocess_bulk_collect_into(mut sql: String, count: &mut usize) -> String {
        const KEYWORD: &str = "BULK COLLECT INTO";
        loop {
            let pos = match Self::find_ci(&sql, KEYWORD) {
                Some(p) => p,
                None => break,
            };
            let after = pos + KEYWORD.len();
            let bytes = sql.as_bytes();
            let mut p = after;
            // skip whitespace between INTO and the collection variable
            while p < bytes.len() && bytes[p].is_ascii_whitespace() {
                p += 1;
            }
            // read the variable name (identifier chars + dots for qualified names)
            let var_start = p;
            while p < bytes.len() {
                let c = bytes[p];
                if c.is_ascii_alphanumeric() || c == b'_' || c == b'.' {
                    p += 1;
                } else {
                    break;
                }
            }
            if var_start == p {
                // no identifier followed the keyword — bail out to avoid looping
                break;
            }
            let var_name = sql[var_start..p].to_string();
            let before = &sql[..pos];
            let tail = &sql[p..];
            sql = format!("{before}/* BULK_COLLECT_INTO: {var_name} */{tail}");
            *count += 1;
        }
        sql
    }

    /// Strip a leading `FORALL <range> ` prefix and preserve it as a comment,
    /// then normalise the resulting DML so `sqlparser-rs` can parse it.
    ///
    /// Example: `FORALL i IN 1..c.COUNT INSERT INTO t VALUES c(i)`
    ///       → `/* FORALL: i IN 1..c.COUNT */ INSERT INTO t VALUES (c(i))`
    ///
    /// The paren-less `VALUES c(i)` (Oracle FORALL bulk-bind form) is wrapped
    /// in parentheses so the standard `VALUES (...)` grammar accepts it.
    fn preprocess_forall(sql: String, count: &mut usize) -> String {
        let leading_ws = sql.len() - sql.trim_start().len();
        let trimmed = &sql[leading_ws..];
        if !Self::starts_with_kw_ci(trimmed, "FORALL") {
            return sql;
        }
        let forall_pos = leading_ws;
        let after_forall = forall_pos + "FORALL".len();
        let rest = &sql[after_forall..];
        let dml_in_rest = match Self::find_any_kw_ci(rest, &["INSERT", "UPDATE", "DELETE", "MERGE"]) {
            Some(p) => p,
            None => return sql,
        };
        let dml_pos = after_forall + dml_in_rest;
        let forall_clause = sql[after_forall..dml_pos].trim().to_string();
        let dml_stmt = Self::wrap_forall_values(sql[dml_pos..].to_string());
        *count += 1;
        format!("/* FORALL: {forall_clause} */ {dml_stmt}")
    }

    /// Strip `INTO :<var>` from a trailing `RETURNING <col> INTO :<var>`
    /// clause, keeping `RETURNING <col>` (which `sqlparser-rs` parses natively)
    /// and preserving the bound variable in a comment.
    ///
    /// Example: `... RETURNING employee_id INTO :id`
    ///       → `... RETURNING employee_id /* RETURNING_INTO: :id */`
    fn preprocess_returning_into(mut sql: String, count: &mut usize) -> String {
        loop {
            let ret_pos = match Self::find_kw_ci(&sql, "RETURNING") {
                Some(p) => p,
                None => break,
            };
            let after_ret = ret_pos + "RETURNING".len();
            let rest = &sql[after_ret..];
            let into_in_rest = match Self::find_kw_ci(rest, "INTO") {
                Some(p) => p,
                None => break, // RETURNING without INTO — nothing to strip
            };
            let into_pos = after_ret + into_in_rest;
            let after_into = into_pos + "INTO".len();
            let bytes = sql.as_bytes();
            let mut p = after_into;
            while p < bytes.len() && bytes[p].is_ascii_whitespace() {
                p += 1;
            }
            let var_start = p;
            while p < bytes.len() {
                let c = bytes[p];
                if c.is_ascii_whitespace() || c == b';' {
                    break;
                }
                p += 1;
            }
            if var_start == p {
                break;
            }
            let var_name = sql[var_start..p].to_string();
            let before = &sql[..into_pos];
            let tail = &sql[p..];
            sql = format!("{before}/* RETURNING_INTO: {var_name} */{tail}");
            *count += 1;
        }
        sql
    }

    /// Wrap a paren-less `VALUES <expr>` (Oracle FORALL bulk-bind form) as
    /// `VALUES (<expr>)` so `sqlparser-rs`'s standard VALUES grammar accepts it.
    fn wrap_forall_values(dml: String) -> String {
        let v_pos = match Self::find_kw_ci(&dml, "VALUES") {
            Some(p) => p,
            None => return dml,
        };
        let after_values = v_pos + "VALUES".len();
        let bytes = dml.as_bytes();
        let mut p = after_values;
        while p < bytes.len() && bytes[p].is_ascii_whitespace() {
            p += 1;
        }
        if p >= bytes.len() || bytes[p] == b'(' {
            return dml; // already parenthesised (or empty) — nothing to do
        }
        let before = &dml[..after_values];
        let mut rest = &dml[p..];
        let mut semi = "";
        if rest.ends_with(';') {
            rest = &rest[..rest.len() - 1];
            semi = ";";
        }
        let rest_trimmed = rest.trim_end();
        format!("{before} ({rest_trimmed}){semi}")
    }

    // ---- Oracle XML function rewrites -------------------------------------
    // `sqlparser-rs` does not recognise `XMLEXISTS`, `XMLQUERY`, or
    // `XMLSERIALIZE`. We scan for each call, paren/string-match it, and
    // splice in a form `sqlparser-rs` accepts.

    /// Rewrite all Oracle XML function calls in `sql`. Mutates `count` by the
    /// number of calls rewritten. Returns the new SQL string.
    fn rewrite_xml_functions(mut sql: String, count: &mut usize) -> String {
        sql = Self::rewrite_xml_exists(sql, count);
        sql = Self::rewrite_xml_query(sql, count);
        sql = Self::rewrite_xmlserialize(sql, count);
        sql
    }

    /// `XMLEXISTS('/path' PASSING col [BY VALUE])` → `(col.exist('/path') = 1)`
    fn rewrite_xml_exists(mut sql: String, count: &mut usize) -> String {
        while let Some((start, end, replacement)) =
            Self::match_xml_path_call(&sql, "XMLEXISTS", true)
        {
            sql = Self::splice(&sql, start, end, &replacement);
            *count += 1;
        }
        sql
    }

    /// `XMLQUERY('/path' PASSING col [BY VALUE] RETURNING CONTENT)` → `col.query('/path')`
    fn rewrite_xml_query(mut sql: String, count: &mut usize) -> String {
        while let Some((start, end, replacement)) =
            Self::match_xml_path_call(&sql, "XMLQUERY", false)
        {
            sql = Self::splice(&sql, start, end, &replacement);
            *count += 1;
        }
        sql
    }

    /// `XMLSERIALIZE(DOCUMENT|CONTENT col AS <type>)` → `CAST(col AS NVARCHAR(MAX))`
    fn rewrite_xmlserialize(mut sql: String, count: &mut usize) -> String {
        while let Some((start, end, replacement)) = Self::match_xmlserialize(&sql) {
            sql = Self::splice(&sql, start, end, &replacement);
            *count += 1;
        }
        sql
    }

    /// Match a call of the form `KEYWORD('/path' PASSING col ...)`.
    ///
    /// When `wrap_eq_one` is true, the replacement is `(col.exist('/path') = 1)`;
    /// otherwise it is `col.query('/path')`. Returns `(start_byte, end_byte, replacement)`
    /// where the byte range covers the keyword through the closing paren
    /// (`end` is exclusive).
    fn match_xml_path_call(
        s: &str,
        keyword: &str,
        wrap_eq_one: bool,
    ) -> Option<(usize, usize, String)> {
        let kw_start = Self::find_kw_ci(s, keyword)?;
        let open = Self::next_open_paren(s, kw_start + keyword.len())?;
        let close = Self::find_matching_paren(s, open)?;
        let args = &s[open + 1..close];

        let path = Self::extract_first_string_literal(args)?;
        let passing_idx = Self::find_kw_ci(args, "PASSING")?;
        let col_raw = &args[passing_idx + "PASSING".len()..];
        // The column reference extends until the next optional clause keyword
        // (`BY VALUE`, `RETURNING`, `EVALNAME`, ...) — or end of args.
        let col_end = Self::find_any_kw_ci(col_raw, &["BY VALUE", "BY REF", "RETURNING", "EVALNAME"])
            .unwrap_or(col_raw.len());
        let col = col_raw[..col_end].trim();
        if col.is_empty() {
            return None;
        }

        let replacement = if wrap_eq_one {
            format!("({col}.exist('{path}') = 1)")
        } else {
            format!("{col}.query('{path}')")
        };
        Some((kw_start, close + 1, replacement))
    }

    /// Match `XMLSERIALIZE(DOCUMENT|CONTENT col AS <type>)` and emit
    /// `CAST(col AS NVARCHAR(MAX))`.
    fn match_xmlserialize(s: &str) -> Option<(usize, usize, String)> {
        let kw_start = Self::find_kw_ci(s, "XMLSERIALIZE")?;
        let open = Self::next_open_paren(s, kw_start + "XMLSERIALIZE".len())?;
        let close = Self::find_matching_paren(s, open)?;
        let args = &s[open + 1..close];

        // Strip the optional leading DOCUMENT / CONTENT keyword.
        let mut rest = args.trim_start();
        for prefix in &["DOCUMENT", "CONTENT"] {
            if Self::starts_with_kw_ci(rest, prefix) {
                rest = rest[prefix.len()..].trim_start();
                break;
            }
        }

        // Split on the `AS` that separates the column from the target type.
        let as_idx = Self::find_kw_ci(rest, "AS")?;
        let col = rest[..as_idx].trim();
        if col.is_empty() {
            return None;
        }

        let replacement = format!("CAST({col} AS NVARCHAR(MAX))");
        Some((kw_start, close + 1, replacement))
    }

    /// Handle Oracle VIEW clauses that `sqlparser-rs` does not recognise.
    ///   CREATE OR REPLACE FORCE VIEW  → CREATE OR REPLACE /* FORCE_VIEW */ VIEW
    ///   ... WITH CHECK OPTION            → ... /* WITH_CHECK_OPTION */
    ///   ... WITH READ ONLY               → ... /* WITH_READ_ONLY */
    fn preprocess_view_clauses(sql: String, count: &mut usize) -> String {
        let mut sql = sql;

        // 1. Strip FORCE from CREATE OR REPLACE FORCE VIEW
        if let Some(pos) = Self::find_ci(&sql, "OR REPLACE FORCE VIEW") {
            let force_start = pos + "OR REPLACE ".len();
            sql = Self::splice(&sql, force_start, force_start + "FORCE ".len(), "/* FORCE_VIEW */ ");
            *count += 1;
        } else if let Some(pos) = Self::find_ci(&sql, "CREATE FORCE VIEW") {
            let force_start = pos + "CREATE ".len();
            sql = Self::splice(&sql, force_start, force_start + "FORCE ".len(), "/* FORCE_VIEW */ ");
            *count += 1;
        }

        // 2. Strip trailing WITH CHECK OPTION
        let trimmed = sql.trim_end();
        if let Some(pos) = Self::find_ci(trimmed, "WITH CHECK OPTION") {
            if pos + "WITH CHECK OPTION".len() == trimmed.len() {
                let base = sql[..pos].trim_end();
                sql = format!("{base} /* WITH_CHECK_OPTION */");
                *count += 1;
            }
        }

        // 3. Strip trailing WITH READ ONLY
        let trimmed = sql.trim_end();
        if let Some(pos) = Self::find_ci(trimmed, "WITH READ ONLY") {
            if pos + "WITH READ ONLY".len() == trimmed.len() {
                let base = sql[..pos].trim_end();
                sql = format!("{base} /* WITH_READ_ONLY */");
                *count += 1;
            }
        }

        sql
    }

    /// `ORDER SIBLINGS BY <cols>` → `ORDER BY <cols> /* SIBLINGS */`.
    ///
    /// `sqlparser-rs` does not recognise the `SIBLINGS` keyword after `ORDER`.
    /// We strip it (preserving the info as a comment) so the surrounding
    /// SELECT parses cleanly. Hierarchical ordering semantics are preserved
    /// by the recursive CTE rewrite in the IR phase.
    fn preprocess_order_siblings_by(sql: String, count: &mut usize) -> String {
        let mut out = String::with_capacity(sql.len());
        let mut i = 0;
        let bytes = sql.as_bytes();
        while i < bytes.len() {
            // Look for "ORDER" as a whole word (case-insensitive)
            if i + 5 <= bytes.len()
                && bytes[i..i + 5].eq_ignore_ascii_case(b"ORDER")
                && (i == 0 || !Self::is_ident_byte(bytes[i - 1]))
                && (i + 5 == bytes.len() || !Self::is_ident_byte(bytes[i + 5]))
            {
                out.push_str(&sql[i..i + 5]);
                let mut j = i + 5;
                // Skip whitespace
                while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                    out.push(bytes[j] as char);
                    j += 1;
                }
                // Check for "SIBLINGS"
                if j + 8 <= bytes.len() && bytes[j..j + 8].eq_ignore_ascii_case(b"SIBLINGS")
                    && (j + 8 == bytes.len() || !Self::is_ident_byte(bytes[j + 8]))
                {
                    // Skip "SIBLINGS" + whitespace
                    let mut k = j + 8;
                    while k < bytes.len() && bytes[k].is_ascii_whitespace() {
                        out.push(bytes[k] as char);
                        k += 1;
                    }
                    // Append the comment marker
                    out.push_str("/* SIBLINGS */ ");
                    *count += 1;
                    i = k;
                    continue;
                }
                i = j;
                continue;
            }
            out.push(bytes[i] as char);
            i += 1;
        }
        out
    }

    // ---- Oracle Flashback (temporal) clause rewrites -----------------------
    // `sqlparser-rs` does not recognise Oracle's `AS OF TIMESTAMP`,
    // `AS OF SCN`, or `VERSIONS BETWEEN TIMESTAMP ... AND ...` syntax.
    // We strip the clause and preserve it as a `/* ... */` comment so the
    // surrounding SELECT parses cleanly and downstream phases can recover
    // the temporal semantics if needed.

    /// Rewrite all Oracle Flashback clauses in `sql`. Mutates `count` by the
    /// number of clauses rewritten. Returns the new SQL string.
    fn rewrite_flashback(mut sql: String, count: &mut usize) -> String {
        sql = Self::rewrite_as_of(sql, count);
        sql = Self::rewrite_versions_between(sql, count);
        sql
    }

    /// `AS OF TIMESTAMP (expr)`  → `/* FLASHBACK_AS_OF: expr */`
    /// `AS OF SCN <n>`           → `/* FLASHBACK_AS_OF_SCN: <n> */`
    ///
    /// Only matches `AS OF` when followed (after whitespace) by `TIMESTAMP`
    /// or `SCN`, so other uses of the phrase `AS OF` (e.g. MSSQL
    /// `FOR SYSTEM_TIME AS OF`) are left untouched.
    fn rewrite_as_of(mut sql: String, count: &mut usize) -> String {
        let mut search_from = 0;
        while search_from < sql.len() {
            let as_of_pos = match Self::find_kw_ci(&sql[search_from..], "AS OF") {
                Some(p) => search_from + p,
                None => break,
            };
            let after_as_of = as_of_pos + "AS OF".len();
            let bytes = sql.as_bytes();
            let mut p = after_as_of;
            while p < bytes.len() && bytes[p].is_ascii_whitespace() {
                p += 1;
            }
            if p >= bytes.len() {
                break;
            }

            if Self::starts_with_kw_ci(&sql[p..], "TIMESTAMP") {
                let after_ts = p + "TIMESTAMP".len();
                let open = match Self::next_open_paren(&sql, after_ts) {
                    Some(o) => o,
                    None => {
                        search_from = after_as_of;
                        continue;
                    }
                };
                let close = match Self::find_matching_paren(&sql, open) {
                    Some(c) => c,
                    None => {
                        search_from = after_as_of;
                        continue;
                    }
                };
                let expr = sql[open + 1..close].trim();
                let replacement = format!("/* FLASHBACK_AS_OF: {expr} */");
                sql = Self::splice(&sql, as_of_pos, close + 1, &replacement);
                *count += 1;
                search_from = as_of_pos + replacement.len();
            } else if Self::starts_with_kw_ci(&sql[p..], "SCN") {
                let after_scn = p + "SCN".len();
                let bytes = sql.as_bytes();
                let mut q = after_scn;
                while q < bytes.len() && bytes[q].is_ascii_whitespace() {
                    q += 1;
                }
                let val_start = q;
                while q < bytes.len() {
                    let c = bytes[q];
                    if c.is_ascii_whitespace() || c == b';' {
                        break;
                    }
                    q += 1;
                }
                if val_start == q {
                    search_from = after_as_of;
                    continue;
                }
                let val = sql[val_start..q].trim();
                let replacement = format!("/* FLASHBACK_AS_OF_SCN: {val} */");
                sql = Self::splice(&sql, as_of_pos, q, &replacement);
                *count += 1;
                search_from = as_of_pos + replacement.len();
            } else {
                // `AS OF` not followed by TIMESTAMP/SCN — not a Flashback
                // clause. Skip past this occurrence and keep searching.
                search_from = after_as_of;
            }
        }
        sql
    }

    /// `VERSIONS BETWEEN TIMESTAMP <e1> AND <e2>`
    ///   → `/* FLASHBACK_VERSIONS_BETWEEN: <e1> AND <e2> */`
    ///
    /// The whole `<e1> AND <e2>` span (from after the optional `TIMESTAMP`/
    /// `SCN` keyword up to the next top-level SQL clause keyword or
    /// statement end) is captured verbatim into the comment.
    fn rewrite_versions_between(mut sql: String, count: &mut usize) -> String {
        let mut search_from = 0;
        while search_from < sql.len() {
            let v_pos = match Self::find_kw_ci(&sql[search_from..], "VERSIONS") {
                Some(p) => search_from + p,
                None => break,
            };
            let after_versions = v_pos + "VERSIONS".len();
            let bytes = sql.as_bytes();
            let mut p = after_versions;
            while p < bytes.len() && bytes[p].is_ascii_whitespace() {
                p += 1;
            }
            if p >= bytes.len() {
                break;
            }
            if !Self::starts_with_kw_ci(&sql[p..], "BETWEEN") {
                // `VERSIONS` not followed by `BETWEEN` — not a Flashback
                // clause (could be a column named `versions`). Skip past.
                search_from = after_versions;
                continue;
            }
            let after_between = p + "BETWEEN".len();
            let bytes = sql.as_bytes();
            let mut p2 = after_between;
            while p2 < bytes.len() && bytes[p2].is_ascii_whitespace() {
                p2 += 1;
            }
            // Optional `TIMESTAMP` / `SCN` keyword between BETWEEN and the
            // first expression — Oracle's grammar requires one of them.
            let expr_start;
            if Self::starts_with_kw_ci(&sql[p2..], "TIMESTAMP") {
                expr_start = p2 + "TIMESTAMP".len();
            } else if Self::starts_with_kw_ci(&sql[p2..], "SCN") {
                expr_start = p2 + "SCN".len();
            } else {
                expr_start = p2;
            }
            let bytes = sql.as_bytes();
            let mut q = expr_start;
            while q < bytes.len() && bytes[q].is_ascii_whitespace() {
                q += 1;
            }
            let expr_begin = q;
            // Scan to end of statement or next top-level SQL clause keyword.
            let end = Self::scan_to_clause_end(&sql, expr_begin);
            let exprs = sql[expr_begin..end].trim();
            let replacement = format!("/* FLASHBACK_VERSIONS_BETWEEN: {exprs} */");
            sql = Self::splice(&sql, v_pos, end, &replacement);
            *count += 1;
            search_from = v_pos + replacement.len();
        }
        sql
    }

    /// Scan from `from` to find the end of the current SQL clause, respecting
    /// paren nesting and string literals. Stops at a top-level (depth 0)
    /// clause keyword (`WHERE` / `GROUP` / `ORDER` / `HAVING` / `CONNECT` /
    /// `START` / `MODEL` / `WINDOW` / `LIMIT` / `OFFSET` / `FETCH` / `FOR` /
    /// `UNION` / `MINUS` / `INTERSECT` / `EXCEPT` / `RETURNING`) or at `;` /
    /// EOF. Returns the byte offset of the boundary (exclusive end of the
    /// clause).
    fn scan_to_clause_end(s: &str, from: usize) -> usize {
        let bytes = s.as_bytes();
        let mut i = from;
        let mut depth: i32 = 0;
        let mut in_string = false;
        let mut quote = b'\'';
        const CLAUSE_KW: &[&str] = &[
            "WHERE",
            "GROUP",
            "ORDER",
            "HAVING",
            "CONNECT",
            "START",
            "MODEL",
            "WINDOW",
            "LIMIT",
            "OFFSET",
            "FETCH",
            "FOR",
            "UNION",
            "MINUS",
            "INTERSECT",
            "EXCEPT",
            "RETURNING",
        ];
        while i < bytes.len() {
            let c = bytes[i];
            if in_string {
                if c == quote {
                    if i + 1 < bytes.len() && bytes[i + 1] == quote {
                        i += 2;
                        continue;
                    }
                    in_string = false;
                }
                i += 1;
                continue;
            }
            match c {
                b'\'' | b'"' => {
                    in_string = true;
                    quote = c;
                    i += 1;
                }
                b'(' => {
                    depth += 1;
                    i += 1;
                }
                b')' => {
                    if depth > 0 {
                        depth -= 1;
                    }
                    i += 1;
                }
                b';' if depth == 0 => return i,
                _ => {
                    if depth == 0 && (i == 0 || !Self::is_ident_byte(bytes[i - 1])) {
                        let rest = &s[i..];
                        for kw in CLAUSE_KW {
                            if Self::starts_with_kw_ci(rest, kw) {
                                let after = i + kw.len();
                                if after == bytes.len()
                                    || !Self::is_ident_byte(bytes[after])
                                {
                                    return i;
                                }
                            }
                        }
                    }
                    i += 1;
                }
            }
        }
        bytes.len()
    }

    // ---- case-insensitive byte-level helpers ----
    // `regex_lite` is a literal-substring shim and cannot express word
    // boundaries or identifier extraction, so these helpers fill that gap
    // for ASCII SQL keywords. They are deliberately small and avoid unicode
    // lowercasing (which could shift byte offsets).

    fn is_ident_byte(c: u8) -> bool {
        c.is_ascii_alphanumeric() || c == b'_'
    }

    /// Count whole-word occurrences of `keyword` (case-insensitive). Increments
    /// `count` by the number of matches. Does not modify the SQL.
    fn count_keyword(haystack: &str, keyword: &str, count: &mut usize) {
        let mut search_from = 0;
        loop {
            match Self::find_kw_ci_from(haystack, keyword, search_from) {
                Some(pos) => {
                    *count += 1;
                    search_from = pos + keyword.len();
                }
                None => break,
            }
        }
    }

    /// Like `find_kw_ci` but with a search-from offset.
    fn find_kw_ci_from(haystack: &str, keyword: &str, from: usize) -> Option<usize> {
        if from >= haystack.len() {
            return None;
        }
        let sub = &haystack[from..];
        Self::find_kw_ci(sub, keyword).map(|p| p + from)
    }

    /// Replace all whole-word occurrences of `keyword` with `replacement`
    /// (case-insensitive). Increments `count` by the number of replacements.
    fn rewrite_keyword_whole_word(haystack: &str, keyword: &str, replacement: &str, count: &mut usize) -> String {
        let mut out = String::with_capacity(haystack.len());
        let mut i = 0;
        let bytes = haystack.as_bytes();
        let kw = keyword.as_bytes();
        while i < bytes.len() {
            if i + kw.len() <= bytes.len()
                && bytes[i..i + kw.len()].eq_ignore_ascii_case(kw)
                && (i == 0 || !Self::is_ident_byte(bytes[i - 1]))
                && (i + kw.len() == bytes.len() || !Self::is_ident_byte(bytes[i + kw.len()]))
            {
                out.push_str(replacement);
                *count += 1;
                i += kw.len();
            } else {
                out.push(bytes[i] as char);
                i += 1;
            }
        }
        out
    }

    /// Replace `KEYWORD(` with `replacement(` (case-insensitive, allowing
    /// optional whitespace between the keyword and `(`). Increments `count`.
    fn rewrite_keyword_with_paren(haystack: &str, keyword: &str, replacement: &str, count: &mut usize) -> String {
        let mut out = String::with_capacity(haystack.len());
        let mut i = 0;
        let bytes = haystack.as_bytes();
        let kw = keyword.as_bytes();
        while i < bytes.len() {
            if i + kw.len() <= bytes.len()
                && bytes[i..i + kw.len()].eq_ignore_ascii_case(kw)
                && (i == 0 || !Self::is_ident_byte(bytes[i - 1]))
            {
                // Check what follows: must be optional whitespace then '('
                let mut j = i + kw.len();
                while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                    j += 1;
                }
                if j < bytes.len() && bytes[j] == b'(' && (i + kw.len() == bytes.len() || !Self::is_ident_byte(bytes[i + kw.len()]) || bytes[i + kw.len()].is_ascii_whitespace()) {
                    out.push_str(replacement);
                    out.push('(');
                    *count += 1;
                    i = j + 1;
                    continue;
                }
            }
            out.push(bytes[i] as char);
            i += 1;
        }
        out
    }

    /// Strip ` FROM DUAL` (case-insensitive, whole-word DUAL). Increments
    /// `count` by the number of strips.
    fn strip_from_dual(haystack: &str, count: &mut usize) -> String {
        let mut out = String::with_capacity(haystack.len());
        let bytes = haystack.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            // Look for "FROM" as a whole word
            if i + 4 <= bytes.len()
                && bytes[i..i + 4].eq_ignore_ascii_case(b"FROM")
                && (i == 0 || !Self::is_ident_byte(bytes[i - 1]))
                && (i + 4 == bytes.len() || !Self::is_ident_byte(bytes[i + 4]))
            {
                // Skip whitespace
                let mut j = i + 4;
                while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                    j += 1;
                }
                // Check for "DUAL" as a whole word
                if j + 4 <= bytes.len() && bytes[j..j + 4].eq_ignore_ascii_case(b"DUAL")
                    && (j + 4 == bytes.len() || !Self::is_ident_byte(bytes[j + 4]))
                {
                    // Skip the entire " FROM DUAL" sequence (and any trailing whitespace)
                    let mut k = j + 4;
                    while k < bytes.len() && bytes[k].is_ascii_whitespace() {
                        k += 1;
                    }
                    *count += 1;
                    i = k;
                    continue;
                }
            }
            out.push(bytes[i] as char);
            i += 1;
        }
        out
    }

    /// Case-insensitive substring search (ASCII). Returns byte offset.
    fn find_ci(haystack: &str, needle: &str) -> Option<usize> {
        let h = haystack.as_bytes();
        let n = needle.as_bytes();
        if n.is_empty() || h.len() < n.len() {
            return None;
        }
        let last = h.len() - n.len();
        let mut i = 0;
        while i <= last {
            if h[i..i + n.len()]
                .iter()
                .zip(n.iter())
                .all(|(a, b)| a.eq_ignore_ascii_case(b))
            {
                return Some(i);
            }
            i += 1;
        }
        None
    }

    /// Case-insensitive whole-word keyword search (ASCII). Returns byte offset.
    /// A word boundary is any non-identifier byte (or string edge).
    fn find_kw_ci(haystack: &str, keyword: &str) -> Option<usize> {
        let h = haystack.as_bytes();
        let n = keyword.as_bytes();
        if n.is_empty() || h.len() < n.len() {
            return None;
        }
        let last = h.len() - n.len();
        let mut i = 0;
        while i <= last {
            if h[i..i + n.len()]
                .iter()
                .zip(n.iter())
                .all(|(a, b)| a.eq_ignore_ascii_case(b))
            {
                let before_ok = i == 0 || !Self::is_ident_byte(h[i - 1]);
                let after_ok = i + n.len() == h.len() || !Self::is_ident_byte(h[i + n.len()]);
                if before_ok && after_ok {
                    return Some(i);
                }
            }
            i += 1;
        }
        None
    }

    /// Earliest whole-word position of any of the given keywords (ASCII, CI).
    fn find_any_kw_ci(haystack: &str, keywords: &[&str]) -> Option<usize> {
        let mut best: Option<usize> = None;
        for kw in keywords {
            if let Some(p) = Self::find_kw_ci(haystack, kw) {
                best = Some(best.map_or(p, |b| b.min(p)));
            }
        }
        best
    }

    /// True if `haystack` starts with `keyword` as a whole word (ASCII, CI).
    fn starts_with_kw_ci(haystack: &str, keyword: &str) -> bool {
        let h = haystack.as_bytes();
        let n = keyword.as_bytes();
        if n.is_empty() || h.len() < n.len() {
            return false;
        }
        if !h[..n.len()]
            .iter()
            .zip(n.iter())
            .all(|(a, b)| a.eq_ignore_ascii_case(b))
        {
            return false;
        }
        if h.len() == n.len() {
            return true;
        }
        !Self::is_ident_byte(h[n.len()])
    }

    /// Replace `s[start..end]` with `replacement` and return the new string.
    fn splice(s: &str, start: usize, end: usize, replacement: &str) -> String {
        let mut out = String::with_capacity(s.len() + replacement.len());
        out.push_str(&s[..start]);
        out.push_str(replacement);
        out.push_str(&s[end..]);
        out
    }

    /// Skip ASCII whitespace from `from` and return the index of the next
    /// `(`. Returns `None` if a non-whitespace, non-`(` byte is hit first.
    fn next_open_paren(s: &str, from: usize) -> Option<usize> {
        let bytes = s.as_bytes();
        let mut i = from;
        while i < bytes.len() {
            match bytes[i] {
                b if b.is_ascii_whitespace() => i += 1,
                b'(' => return Some(i),
                _ => return None,
            }
        }
        None
    }

    /// Given that `s[open] == '('`, return the index of the matching `)`.
    /// Respects nested parens and single/double-quoted string literals
    /// (with SQL-style `''` / `""` escapes).
    fn find_matching_paren(s: &str, open: usize) -> Option<usize> {
        let bytes = s.as_bytes();
        if open >= bytes.len() || bytes[open] != b'(' {
            return None;
        }
        let mut depth = 0;
        let mut in_string = false;
        let mut quote = b'\'';
        let mut i = open;
        while i < bytes.len() {
            let c = bytes[i];
            if in_string {
                if c == quote {
                    if i + 1 < bytes.len() && bytes[i + 1] == quote {
                        i += 2;
                        continue;
                    }
                    in_string = false;
                }
            } else if c == b'\'' || c == b'"' {
                in_string = true;
                quote = c;
            } else if c == b'(' {
                depth += 1;
            } else if c == b')' {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            i += 1;
        }
        None
    }

    /// Extract the contents of the first single-quoted string literal in `s`,
    /// handling SQL `''` escapes. Returns the contents without surrounding quotes.
    fn extract_first_string_literal(s: &str) -> Option<String> {
        let open = s.find('\'')?;
        let mut content = String::new();
        let mut chars = s[open + 1..].chars().peekable();
        while let Some(c) = chars.next() {
            if c == '\'' {
                if chars.peek() == Some(&'\'') {
                    content.push('\'');
                    chars.next();
                    continue;
                }
                return Some(content);
            }
            content.push(c);
        }
        None
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
