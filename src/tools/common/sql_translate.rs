//! T-SQL → DuckDB dialect translation.
//!
//! Direct port of `translate_tsql_to_duckdb()` and `split_statements()`
//! from `scripts/verify_ops.py`.
//!
//! Conservative — only syntactically required changes. Semantic rewrites
//! (XML, spatial, temporal) are done in the op_NN.sql files themselves.

use regex::Regex;

/// Minimal T-SQL → DuckDB dialect translation.
///
/// Applies the following transformations:
/// - Strip block comments `/* ... */` and line comments `-- ...`
/// - Remove T-SQL batch/session primitives (`GO`, `SET NOCOUNT ON`, `USE`, `PRINT`, etc.)
/// - `SELECT TOP N` → `SELECT ... LIMIT N`
/// - `ISNULL(a, b)` → `COALESCE(a, b)`
/// - `GETDATE()` / `SYSDATETIME()` → `CURRENT_TIMESTAMP`
/// - `CHARINDEX(a, b)` → `instr(b, a)` (arg order flipped)
/// - `LEN(x)` → `length(x)`
/// - `LTRIM(RTRIM(x))` → `trim(trim(x))`
/// - `N'...'` → `'...'`
pub fn translate_tsql_to_duckdb(sql: &str) -> String {
    let mut s = sql.to_string();

    // Strip block comments /* ... */ (single line, multiline)
    let block_re = Regex::new(r"/\*.*?\*/").unwrap();
    s = block_re.replace_all(&s, "").into_owned();

    // Strip line comments -- ... but keep newlines
    let line_re = Regex::new(r"--[^\n]*").unwrap();
    s = line_re.replace_all(&s, "").into_owned();

    // Remove T-SQL batch / session primitives
    let go_re = Regex::new(r"(?i)\bGO\b").unwrap();
    s = go_re.replace_all(&s, ";").into_owned();

    let nocount_re = Regex::new(r"(?i)SET\s+NOCOUNT\s+ON\s*;").unwrap();
    s = nocount_re.replace_all(&s, "").into_owned();

    let quoted_re = Regex::new(r"(?i)SET\s+QUOTED_IDENTIFIER\s+ON\s*;").unwrap();
    s = quoted_re.replace_all(&s, "").into_owned();

    let use_re = Regex::new(r"(?i)USE\s+\w+\s*;").unwrap();
    s = use_re.replace_all(&s, "").into_owned();

    let print_re = Regex::new(r#"(?i)PRINT\s+N?'[^']*'\s*;"#).unwrap();
    s = print_re.replace_all(&s, "").into_owned();

    let option_re = Regex::new(r"(?i)OPTION\s*\([^)]*\)").unwrap();
    s = option_re.replace_all(&s, "").into_owned();

    // DECLARE @var TYPE [= value]; → remove
    let declare_re = Regex::new(r"(?i)DECLARE\s+@\w+\s+\w+(?:\([^)]*\))?\s*(=\s*[^;]+)?;").unwrap();
    s = declare_re.replace_all(&s, "").into_owned();

    // SET @var = value; → remove
    let set_var_re = Regex::new(r"(?i)SET\s+@\w+\s*=\s*[^;]+;").unwrap();
    s = set_var_re.replace_all(&s, "").into_owned();

    // SELECT TOP N ... → SELECT ... LIMIT N
    // Handle: SELECT TOP (N) ... and SELECT TOP N ...
    let top_re = Regex::new(r"(?i)\bSELECT\s+TOP\s*\(?(\d+)\)?").unwrap();
    s = top_re
        .replace_all(&s, |caps: &regex::Captures| {
            format!("__TOPNLIMIT_{}__ SELECT ", &caps[1])
        })
        .into_owned();

    // If we have a TOP marker, append LIMIT N at the end
    let top_marker_re = Regex::new(r"__TOPNLIMIT_(\d+)__\s*SELECT\s").unwrap();
    if let Some(m) = top_marker_re.captures(&s) {
        let top_n = m[1].to_string();
        let strip_marker_re = Regex::new(r"__TOPNLIMIT_\d+__\s*SELECT\s").unwrap();
        s = strip_marker_re.replace_all(&s, "SELECT ").into_owned();
        // Append LIMIT N at end (after stripping trailing semicolons)
        s = s.trim_end().trim_end_matches(';').to_string();
        let limit_re = Regex::new(r"(?i)\bLIMIT\s+\d+\s*$").unwrap();
        if limit_re.is_match(&s) {
            s = limit_re.replace(&s, format!("LIMIT {}", top_n)).into_owned();
        } else {
            s.push_str(&format!("\nLIMIT {}", top_n));
        }
    }

    // ISNULL(a, b) → COALESCE(a, b)
    let isnull_re = Regex::new(r"(?i)\bISNULL\s*\(").unwrap();
    s = isnull_re.replace_all(&s, "COALESCE(").into_owned();

    // GETDATE() → CURRENT_TIMESTAMP
    let getdate_re = Regex::new(r"(?i)\bGETDATE\s*\(\s*\)").unwrap();
    s = getdate_re.replace_all(&s, "CURRENT_TIMESTAMP").into_owned();

    // SYSDATETIME() → CURRENT_TIMESTAMP
    let sysdt_re = Regex::new(r"(?i)\bSYSDATETIME\s*\(\s*\)").unwrap();
    s = sysdt_re.replace_all(&s, "CURRENT_TIMESTAMP").into_owned();

    // CHARINDEX(a, b) → instr(b, a) (arg order flipped)
    let charindex_re = Regex::new(r"(?i)\bCHARINDEX\s*\(\s*([^,]+),\s*([^,)]+)").unwrap();
    s = charindex_re
        .replace_all(&s, |caps: &regex::Captures| {
            format!("instr({}, {}", &caps[2], &caps[1])
        })
        .into_owned();

    // LEN(x) → length(x)
    let len_re = Regex::new(r"(?i)\bLEN\s*\(").unwrap();
    s = len_re.replace_all(&s, "length(").into_owned();

    // LTRIM(RTRIM(x)) → trim(trim(x))
    let ltrim_re = Regex::new(r"(?i)\bLTRIM\s*\(\s*RTRIM\s*\(").unwrap();
    s = ltrim_re.replace_all(&s, "trim(trim(").into_owned();

    // N'...' → '...'
    let nprefix_re = Regex::new(r"\bN'").unwrap();
    s = nprefix_re.replace_all(&s, "'").into_owned();

    s
}

/// Split SQL on semicolons not inside single-quoted strings.
///
/// Direct port of `split_statements()` from `verify_ops.py`.
pub fn split_statements(sql: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut buf = String::new();
    let mut in_str = false;

    for c in sql.chars() {
        if c == '\'' {
            in_str = !in_str;
            buf.push(c);
        } else if c == ';' && !in_str {
            let stmt = buf.trim().to_string();
            if !stmt.is_empty() {
                out.push(stmt);
            }
            buf.clear();
        } else {
            buf.push(c);
        }
    }
    let last = buf.trim().to_string();
    if !last.is_empty() {
        out.push(last);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_isnull_to_coalesce() {
        let sql = "SELECT ISNULL(a, b) FROM t";
        let result = translate_tsql_to_duckdb(sql);
        assert!(result.contains("COALESCE(a, b)"));
        assert!(!result.contains("ISNULL"));
    }

    #[test]
    fn test_getdate() {
        let sql = "SELECT GETDATE() AS now";
        let result = translate_tsql_to_duckdb(sql);
        assert!(result.contains("CURRENT_TIMESTAMP"));
    }

    #[test]
    fn test_top_n_to_limit() {
        let sql = "SELECT TOP 10 * FROM Employees ORDER BY ID";
        let result = translate_tsql_to_duckdb(sql);
        assert!(result.contains("LIMIT 10"));
        assert!(!result.contains("TOP"));
    }

    #[test]
    fn test_strip_comments() {
        let sql = "SELECT 1 /* comment */ -- line\nFROM t";
        let result = translate_tsql_to_duckdb(sql);
        assert!(!result.contains("comment"));
        assert!(!result.contains("line"));
    }

    #[test]
    fn test_split_statements() {
        let sql = "SELECT 1; SELECT 'hello; world'; SELECT 3";
        let stmts = split_statements(sql);
        assert_eq!(stmts.len(), 3);
        assert_eq!(stmts[1], "SELECT 'hello; world'");
    }

    #[test]
    fn test_charindex() {
        let sql = "SELECT CHARINDEX('abc', 'xabc')";
        let result = translate_tsql_to_duckdb(sql);
        assert!(result.contains("instr('xabc', 'abc')"));
    }

    #[test]
    fn test_n_prefix() {
        let sql = "SELECT N'hello'";
        let result = translate_tsql_to_duckdb(sql);
        assert!(result.contains("'hello'"));
        assert!(!result.contains("N'"));
    }
}
