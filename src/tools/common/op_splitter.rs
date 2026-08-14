//! Regex-based op file splitting.
//!
//! Direct port of `split_ops()` from `scripts/split_ops.py` and the
//! `split_ops()` function from `scripts/mssql_runner/split_and_run.py`.
//!
//! Splits a monolithic MSSQL SQL file into individual `op_NN.sql` files
//! using the `-- OP N:` header pattern.

use regex::Regex;

/// A single split operation: its number and SQL content.
#[derive(Debug, Clone)]
pub struct SplitOp {
    pub op_num: u32,
    pub sql: String,
}

/// Split a monolithic SQL file into individual operations.
///
/// Looks for headers matching `-- OP N:` and slices the text between them.
///
/// Direct port of `split_ops()` from `split_ops.py`.
pub fn split_ops(sql: &str) -> Vec<SplitOp> {
    let re = Regex::new(r"(?m)^--\s*OP\s+(\d+)\s*:").unwrap();
    let matches: Vec<(usize, u32)> = re
        .captures_iter(sql)
        .filter_map(|c| {
            let pos = c.get(0).unwrap().start();
            let num: u32 = c[1].parse().unwrap_or(0);
            Some((pos, num))
        })
        .collect();

    if matches.is_empty() {
        return Vec::new();
    }

    let mut ops = Vec::new();
    for i in 0..matches.len() {
        let (start, num) = matches[i];
        let end = if i + 1 < matches.len() {
            matches[i + 1].0
        } else {
            sql.len()
        };
        let chunk = &sql[start..end];
        ops.push(SplitOp {
            op_num: num,
            sql: chunk.to_string(),
        });
    }
    ops
}

/// Write split ops to individual files in the given directory.
///
/// Files are named `op_NN.sql` (zero-padded to 2 digits).
pub fn write_ops(ops: &[SplitOp], out_dir: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(out_dir)?;
    for op in ops {
        let filename = format!("op_{:02}.sql", op.op_num);
        let path = out_dir.join(filename);
        std::fs::write(path, &op.sql)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_ops() {
        let sql = "-- OP 1: First op\nSELECT 1;\n-- OP 2: Second op\nSELECT 2;\n-- OP 50: Last\nSELECT 50;";
        let ops = split_ops(sql);
        assert_eq!(ops.len(), 3);
        assert_eq!(ops[0].op_num, 1);
        assert!(ops[0].sql.contains("First op"));
        assert_eq!(ops[1].op_num, 2);
        assert!(ops[1].sql.contains("Second op"));
        assert_eq!(ops[2].op_num, 50);
        assert!(ops[2].sql.contains("Last"));
    }

    #[test]
    fn test_split_ops_empty() {
        let sql = "SELECT 1;";
        let ops = split_ops(sql);
        assert!(ops.is_empty());
    }

    #[test]
    fn test_split_ops_preserves_content() {
        let sql = "-- OP 1: Test\nSELECT * FROM t;\n-- OP 2: Next\nSELECT 2;";
        let ops = split_ops(sql);
        assert_eq!(ops.len(), 2);
        assert!(ops[0].sql.contains("SELECT * FROM t;"));
    }
}
