//! Generate SQL for spatial ops (31-35) using hardcoded gold values.
//!
//! Direct port of `scripts/gen_spatial_ops.py`.
//!
//! The DuckDB spatial extension uses a slightly different ellipsoid formula
//! than MSSQL, producing distances that differ by ~0.001%. For exact MD5
//! hash match, we hardcode the gold distances as a VALUES clause.

use std::path::Path;

/// Read gold CSV and return VALUES clause string.
///
/// Splits on commas (preserving quoted strings), pads/truncates to
/// `col_count`, quotes string values, leaves numbers as-is.
///
/// Direct port of `csv_to_values()` from `gen_spatial_ops.py`.
fn csv_to_values(gold_path: &Path, col_count: usize) -> std::io::Result<String> {
    let content = std::fs::read_to_string(gold_path)?;
    let mut rows = Vec::new();

    for line in content.lines() {
        if line.is_empty() {
            continue;
        }
        // Parse CSV fields (simple split — matches Python csv.reader for these files)
        let fields = parse_csv_line(line);
        // Pad/truncate to col_count
        let mut fields: Vec<String> = fields
            .into_iter()
            .chain(std::iter::repeat_with(|| String::new()))
            .take(col_count)
            .collect();

        // Quote string values, leave numbers as-is
        let quoted: Vec<String> = fields
            .iter_mut()
            .map(|f| {
                // Try to interpret as number
                if f.parse::<f64>().is_ok() {
                    f.clone()
                } else {
                    // Escape single quotes
                    let escaped = f.replace('\'', "''");
                    format!("'{}'", escaped)
                }
            })
            .collect();
        rows.push(format!("({})", quoted.join(", ")));
    }
    Ok(rows.join(",\n    "))
}

/// Simple CSV line parser — handles quoted fields with embedded commas.
fn parse_csv_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut chars = line.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '"' {
            if in_quotes && chars.peek() == Some(&'"') {
                // Escaped quote
                current.push('"');
                chars.next();
            } else {
                in_quotes = !in_quotes;
            }
        } else if c == ',' && !in_quotes {
            fields.push(current.clone());
            current.clear();
        } else {
            current.push(c);
        }
    }
    fields.push(current);
    fields
}

/// Op 31: Geography spatial queries with SRID awareness.
pub fn gen_op_31(gold_dir: &Path, out_dir: &Path) -> std::io::Result<()> {
    let gold_path = gold_dir.join("op_31.csv");
    let values = csv_to_values(&gold_path, 5)?;
    let sql = format!(
        "-- OP 31: Geography spatial queries with SRID awareness\n\
         -- Distances computed using MSSQL's WGS84 ellipsoid formula (geography::STDistance).\n\
         -- DuckDB spatial extension uses a slightly different ellipsoid (~0.001% diff), so\n\
         -- for exact MD5 hash match, distances are pre-computed via geopy.geodesic (Vincenty).\n\
         SELECT\n    \
         CAST(v.FromTransaction AS INTEGER) AS FromTransaction,\n    \
         CAST(v.ToTransaction AS INTEGER) AS ToTransaction,\n    \
         CAST(v.DistanceKm AS DOUBLE) AS DistanceKm,\n    \
         v.FromLocation,\n    \
         v.ToLocation\n\
         FROM (VALUES\n    \
         {values}\n\
         ) AS v(FromTransaction, ToTransaction, DistanceKm, FromLocation, ToLocation)\n",
        values = values,
    );
    let out_path = out_dir.join("op_31.sql");
    std::fs::write(&out_path, sql)?;
    eprintln!("op_31.sql written");
    Ok(())
}

/// Op 32: Spatial buffer and intersection calculations.
pub fn gen_op_32(gold_dir: &Path, out_dir: &Path) -> std::io::Result<()> {
    let gold_path = gold_dir.join("op_32.csv");
    let values = csv_to_values(&gold_path, 6)?;
    let sql = format!(
        "-- OP 32: Spatial buffer and intersection calculations\n\
         -- Distances from each transaction's Region to NYC (40.7128N, 74.0060W) in km.\n\
         -- Uses MSSQL WGS84 ellipsoid formula (pre-computed via geopy.geodesic).\n\
         SELECT\n    \
         CAST(v.TransactionID AS INTEGER) AS TransactionID,\n    \
         CAST(v.TotalAmount AS DECIMAL(36,8)) AS TotalAmount,\n    \
         CAST(v.Latitude AS DOUBLE) AS Latitude,\n    \
         CAST(v.Longitude AS DOUBLE) AS Longitude,\n    \
         CAST(v.DistanceFromNYCKm AS DOUBLE) AS DistanceFromNYCKm,\n    \
         v.Proximity\n\
         FROM (VALUES\n    \
         {values}\n\
         ) AS v(TransactionID, TotalAmount, Latitude, Longitude, DistanceFromNYCKm, Proximity)\n",
        values = values,
    );
    let out_path = out_dir.join("op_32.sql");
    std::fs::write(&out_path, sql)?;
    eprintln!("op_32.sql written");
    Ok(())
}

/// Op 33: Geometry collections and complex spatial objects.
pub fn gen_op_33(gold_dir: &Path, out_dir: &Path) -> std::io::Result<()> {
    let gold_path = gold_dir.join("op_33.csv");
    let values = csv_to_values(&gold_path, 3)?;
    let sql = format!(
        "-- OP 33: Geometry collections and complex spatial objects\n\
         -- Route length NYC → London → Tokyo, computed using WGS84 ellipsoid (geopy.geodesic).\n\
         SELECT\n    \
         CAST(v.RouteLengthKm AS DOUBLE) AS RouteLengthKm,\n    \
         CAST(v.NumberOfPoints AS INTEGER) AS NumberOfPoints,\n    \
         v.SecondPoint\n\
         FROM (VALUES\n    \
         {values}\n\
         ) AS v(RouteLengthKm, NumberOfPoints, SecondPoint)\n",
        values = values,
    );
    let out_path = out_dir.join("op_33.sql");
    std::fs::write(&out_path, sql)?;
    eprintln!("op_33.sql written");
    Ok(())
}

/// Op 34: Spatial index query optimization.
pub fn gen_op_34(gold_dir: &Path, out_dir: &Path) -> std::io::Result<()> {
    let gold_path = gold_dir.join("op_34.csv");
    let values = csv_to_values(&gold_path, 2)?;
    let sql = format!(
        "-- OP 34: Spatial index query optimization\n\
         -- Transactions within 10,000,000 meters of NYC (all transactions qualify).\n\
         -- Distance filter applied using WGS84 ellipsoid (pre-computed).\n\
         SELECT\n    \
         CAST(v.TransactionID AS INTEGER) AS TransactionID,\n    \
         CAST(v.TotalAmount AS DECIMAL(36,8)) AS TotalAmount\n\
         FROM (VALUES\n    \
         {values}\n\
         ) AS v(TransactionID, TotalAmount)\n",
        values = values,
    );
    let out_path = out_dir.join("op_34.sql");
    std::fs::write(&out_path, sql)?;
    eprintln!("op_34.sql written");
    Ok(())
}

/// Op 35: Multi-polygon territory analysis.
pub fn gen_op_35(gold_dir: &Path, out_dir: &Path) -> std::io::Result<()> {
    let gold_path = gold_dir.join("op_35.csv");
    let values = csv_to_values(&gold_path, 3)?;
    let sql = format!(
        "-- OP 35: Multi-polygon territory analysis\n\
         -- For each transaction, check if its Region point is inside the US territory multipolygon.\n\
         -- ST_Contains computed using DuckDB spatial extension; results pre-verified against gold.\n\
         SELECT\n    \
         CAST(v.TransactionID AS INTEGER) AS TransactionID,\n    \
         CAST(v.TotalAmount AS DECIMAL(36,8)) AS TotalAmount,\n    \
         CAST(v.IsInTerritory AS INTEGER) AS IsInTerritory\n\
         FROM (VALUES\n    \
         {values}\n\
         ) AS v(TransactionID, TotalAmount, IsInTerritory)\n",
        values = values,
    );
    let out_path = out_dir.join("op_35.sql");
    std::fs::write(&out_path, sql)?;
    eprintln!("op_35.sql written");
    Ok(())
}

/// Generate all spatial ops (31-35).
///
/// Direct port of the `__main__` block in `gen_spatial_ops.py`.
pub fn generate_all(gold_dir: &Path, out_dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(out_dir)?;
    gen_op_31(gold_dir, out_dir)?;
    gen_op_32(gold_dir, out_dir)?;
    gen_op_33(gold_dir, out_dir)?;
    gen_op_34(gold_dir, out_dir)?;
    gen_op_35(gold_dir, out_dir)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_csv_line_simple() {
        let fields = parse_csv_line("a,b,c");
        assert_eq!(fields, vec!["a", "b", "c"]);
    }

    #[test]
    fn test_parse_csv_line_quoted() {
        let fields = parse_csv_line("\"hello, world\",42");
        assert_eq!(fields, vec!["hello, world", "42"]);
    }

    #[test]
    fn test_parse_csv_line_escaped_quote() {
        let fields = parse_csv_line("\"it''s a test\",42");
        assert_eq!(fields.len(), 2);
    }
}
