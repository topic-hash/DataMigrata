//! CSV normalization and MD5 hashing for gold-standard comparison.
//!
//! Direct port of `normalize_csv_text()` and `md5_of_text()` from
//! `scripts/verify_ops.py`.

use super::value_fmt::normalize_dt_str;
use md5::compute;

/// Compute the MD5 hash of a text string, returning a hex digest.
///
/// Direct port of `md5_of_text()` from `verify_ops.py`.
pub fn md5_of_text(text: &str) -> String {
    format!("{:x}", compute(text.as_bytes()))
}

/// Normalize CSV text for MD5 comparison.
///
/// - rstrip each line
/// - drop trailing blank lines
/// - ensure single trailing newline
/// - normalize all datetime-like tokens to 6-digit microsecond precision
///
/// Direct port of `normalize_csv_text()` from `verify_ops.py`.
pub fn normalize_csv_text(text: &str) -> String {
    let mut lines: Vec<String> = Vec::new();
    for line in text.split('\n') {
        // Replace each datetime-like token in the line
        // Token boundaries: comma, start/end of line
        let parts: Vec<String> = line.split(',').map(normalize_dt_str).collect();
        lines.push(parts.join(",").trim_end().to_string());
    }
    // Drop trailing blank lines
    while lines.last().map(|l| l.is_empty()).unwrap_or(false) {
        lines.pop();
    }
    if lines.is_empty() {
        String::new()
    } else {
        format!("{}\n", lines.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_md5_of_text() {
        let hash = md5_of_text("hello world");
        assert_eq!(hash, "5eb63bbbe01eeed093cb22bb8f5acdc3");
    }

    #[test]
    fn test_normalize_strips_trailing_whitespace() {
        let text = "a,b,c   \nd,e,f\n";
        let result = normalize_csv_text(text);
        assert_eq!(result, "a,b,c\nd,e,f\n");
    }

    #[test]
    fn test_normalize_drops_trailing_blank_lines() {
        let text = "a,b\n\n\n";
        let result = normalize_csv_text(text);
        assert_eq!(result, "a,b\n");
    }

    #[test]
    fn test_normalize_empty() {
        let result = normalize_csv_text("");
        assert_eq!(result, "");
    }

    #[test]
    fn test_normalize_datetime_tokens() {
        let text = "2026-01-15 10:30:00.1234567,42\n";
        let result = normalize_csv_text(text);
        assert_eq!(result, "2026-01-15 10:30:00.123456,42\n");
    }
}
