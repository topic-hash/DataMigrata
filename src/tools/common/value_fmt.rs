//! Value formatting to match MSSQL gold-standard CSV output.
//!
//! Direct port of `fmt_value()`, `_normalize_dt_str()`, and `rows_to_csv()`
//! from `scripts/verify_ops.py`.
//!
//! MSSQL bcp has specific formatting quirks that must be matched exactly:
//! - `NULL` → literal `"NULL"`
//! - `BOOLEAN` → `1`/`0` (MSSQL BIT representation)
//! - `DECIMAL` with `|x| < 1` drops leading zero: `0.0000` → `.0000`
//! - Integer-valued `FLOAT` gets `.0` suffix: `42.0`
//! - `TIMESTAMP` → 6-digit microsecond precision

use regex::Regex;
use rust_decimal::Decimal;

/// Normalize a datetime-like string to 6-digit microsecond precision.
///
/// Truncates the 7th digit (MSSQL datetime2(7) → DuckDB TIMESTAMP(6)),
/// pads shorter strings. Returns the original if not a datetime.
///
/// Direct port of `_normalize_dt_str()` from `verify_ops.py`.
pub fn normalize_dt_str(s: &str) -> String {
    let re = Regex::new(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d{1,7}))?$").unwrap();
    match re.captures(s) {
        None => s.to_string(),
        Some(caps) => {
            let base = &caps[1];
            let frac = caps.get(2).map(|m| m.as_str()).unwrap_or("");
            // Pad/truncate to exactly 6 digits (DuckDB TIMESTAMP precision)
            let mut frac6 = frac.to_string();
            while frac6.len() < 6 {
                frac6.push('0');
            }
            frac6.truncate(6);
            format!("{}.{}", base, frac6)
        }
    }
}

/// Format a DuckDB value to match MSSQL bcp CSV output.
///
/// This handles the types that DuckDB returns via the `duckdb` crate's
/// `Value` enum. The formatting must match MSSQL bcp exactly for MD5
/// comparison to work.
///
/// Direct port of `fmt_value()` from `verify_ops.py`.
pub fn fmt_value(v: &duckdb::types::Value) -> String {
    use duckdb::types::Value;
    match v {
        Value::Null => "NULL".to_string(),
        Value::Boolean(b) => {
            if *b {
                "1".into()
            } else {
                "0".into()
            }
        }
        Value::TinyInt(i) => i.to_string(),
        Value::SmallInt(i) => i.to_string(),
        Value::Int(i) => i.to_string(),
        Value::BigInt(i) => i.to_string(),
        Value::HugeInt(i) => i.to_string(),
        Value::UTinyInt(u) => u.to_string(),
        Value::USmallInt(u) => u.to_string(),
        Value::UInt(u) => u.to_string(),
        Value::UBigInt(u) => u.to_string(),
        Value::Float(f) => fmt_float(*f as f64),
        Value::Double(f) => fmt_float(*f),
        Value::Decimal(d) => fmt_decimal(*d),
        Value::Text(s) => normalize_dt_str(s),
        Value::Blob(b) => hex::encode(b),
        Value::Timestamp(unit, micros) => {
            // Convert micros to a DateTime, then format with 6-digit precision
            let micros = unit.to_micros(*micros);
            match chrono::DateTime::from_timestamp_micros(micros) {
                Some(dt) => {
                    format!(
                        "{}.{:06}",
                        dt.format("%Y-%m-%d %H:%M:%S"),
                        dt.timestamp_subsec_micros()
                    )
                }
                None => micros.to_string(),
            }
        }
        Value::Date32(days) => {
            // Days since Unix epoch (1970-01-01)
            match chrono::NaiveDate::from_ymd_opt(1970, 1, 1) {
                Some(epoch) => {
                    let date = epoch + chrono::Duration::days(*days as i64);
                    date.format("%Y-%m-%d").to_string()
                }
                None => days.to_string(),
            }
        }
        Value::Time64(unit, micros) => {
            let micros = unit.to_micros(*micros);
            let secs = micros / 1_000_000;
            let rem_micros = micros % 1_000_000;
            let h = secs / 3600;
            let m = (secs % 3600) / 60;
            let s = secs % 60;
            format!("{:02}:{:02}:{:02}.{:06}", h, m, s, rem_micros)
        }
        Value::Interval { months, days, nanos } => {
            format!("{} months {} days {} nanos", months, days, nanos)
        }
        Value::Enum(s) => s.clone(),
        Value::List(items) => {
            let parts: Vec<String> = items.iter().map(fmt_value).collect();
            format!("[{}]", parts.join(", "))
        }
        _ => {
            // Fallback: stringify and normalize datetime-like tokens
            normalize_dt_str(&format!("{:?}", v))
        }
    }
}

/// Format a float to match MSSQL bcp output.
///
/// - Integer-valued floats get `.0` suffix: `42.0`
/// - Other floats use up to 17 significant digits, trailing zeros stripped
fn fmt_float(v: f64) -> String {
    if v == v.trunc() && v.abs() < 1e15 {
        // MSSQL bcp prints integer-valued FLOATs as "N.0" (with .0 suffix)
        return format!("{}.0", v as i64);
    }
    // MSSQL bcp prints floats with up to 17 significant digits, dropping trailing zeros
    // Mimic Python's format(v, '.17g') — general format with 17 significant digits
    let s = format_g(v, 17);
    strip_trailing_zeros(&s)
}

/// Format a decimal to match MSSQL bcp output.
///
/// MSSQL bcp drops the leading 0 before decimal point for |x| < 1:
/// `0.0000` → `.0000`, `-0.5000` → `-.5000`
fn fmt_decimal(d: Decimal) -> String {
    let s = d.to_string();
    if s.starts_with("0.") {
        s[1..].to_string()
    } else if s.starts_with("-0.") {
        format!("-{}", &s[2..])
    } else {
        s
    }
}

/// Mimic Python's `format(v, '.Ng')` — N significant digits, general format.
///
/// Python's `%g` uses scientific notation only when the exponent is < -4 or >= N.
/// Otherwise it uses fixed notation.
fn format_g(v: f64, precision: usize) -> String {
    if v == 0.0 {
        return "0".to_string();
    }
    if v.is_nan() {
        return "NaN".to_string();
    }
    if v.is_infinite() {
        return if v > 0.0 { "inf".to_string() } else { "-inf".to_string() };
    }

    let abs_v = v.abs();
    let exp = abs_v.log10().floor() as i32;

    // Python's %g uses scientific notation when exp < -4 or exp >= precision
    if exp < -4 || exp >= precision as i32 {
        // Scientific notation
        format!("{:.*e}", precision - 1, v)
    } else {
        // Fixed notation with precision - 1 - exp digits after the decimal point
        let decimal_digits = (precision as i32 - 1 - exp).max(0) as usize;
        let s = format!("{:.*}", decimal_digits, v);
        s
    }
}

/// Strip trailing zeros after decimal point (but keep at least one fractional digit).
fn strip_trailing_zeros(s: &str) -> String {
    if !s.contains('.') || s.contains('e') || s.contains('E') {
        return s.to_string();
    }
    let mut result = s.trim_end_matches('0').to_string();
    if result.ends_with('.') {
        result.pop();
    }
    result
}

/// Convert DuckDB result rows to CSV text.
///
/// Each value is formatted via [`fmt_value`], joined by commas, one row per line.
///
/// Direct port of `rows_to_csv()` from `verify_ops.py`.
pub fn rows_to_csv(rows: &[Vec<duckdb::types::Value>]) -> String {
    let mut out = Vec::new();
    for row in rows {
        let parts: Vec<String> = row.iter().map(fmt_value).collect();
        out.push(parts.join(","));
    }
    if out.is_empty() {
        String::new()
    } else {
        format!("{}\n", out.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_dt_str_7_digits() {
        let s = "2026-01-15 10:30:00.1234567";
        assert_eq!(normalize_dt_str(s), "2026-01-15 10:30:00.123456");
    }

    #[test]
    fn test_normalize_dt_str_short() {
        let s = "2026-01-15 10:30:00.12";
        assert_eq!(normalize_dt_str(s), "2026-01-15 10:30:00.120000");
    }

    #[test]
    fn test_normalize_dt_str_no_fraction() {
        let s = "2026-01-15 10:30:00";
        assert_eq!(normalize_dt_str(s), "2026-01-15 10:30:00.000000");
    }

    #[test]
    fn test_normalize_dt_str_not_datetime() {
        let s = "hello world";
        assert_eq!(normalize_dt_str(s), "hello world");
    }

    #[test]
    fn test_fmt_decimal_leading_zero() {
        let d = Decimal::new(0, 4); // 0.0000
        assert_eq!(fmt_decimal(d), ".0000");
    }

    #[test]
    fn test_fmt_decimal_negative_leading_zero() {
        let d = Decimal::new(-5000, 4); // -0.5000
        assert_eq!(fmt_decimal(d), "-.5000");
    }

    #[test]
    fn test_fmt_decimal_normal() {
        let d = Decimal::new(12345, 2); // 123.45
        assert_eq!(fmt_decimal(d), "123.45");
    }
}
