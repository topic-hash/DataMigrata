//! DataMigrata CLI entry point.
//!
//! Usage:
//! ```bash
//! datamigrata translate < input.sql > output.sql
//! datamigrata translate --input mssql.sql --output duckdb.sql
//! datamigrata test50  # run the 50-operation test suite
//! datamigrata generate-ops --out-dir duckdb_migrated
//! datamigrata verify --root /home/z/my-project
//! datamigrata search --root /home/z/my-project
//! datamigrata build-duckdb --db-path analytics.duckdb --data-dir mssql_data
//! datamigrata capture-gold --root /home/z/my-project
//! ```

use std::io::{self, Read};
use std::path::PathBuf;
use clap::{Parser, Subcommand};
use datamigrata::{PipelineIntegration, PipelineResult};

#[derive(Parser, Debug)]
#[command(name = "datamigrata", version, about = "Energy-optimal MSSQL→DuckDB migration compiler")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Translate MSSQL T-SQL to DuckDB SQL.
    Translate {
        /// Input MSSQL T-SQL file (defaults to stdin).
        #[arg(long)]
        input: Option<PathBuf>,
        /// Output DuckDB SQL file (defaults to stdout).
        #[arg(long)]
        output: Option<PathBuf>,
    },
    /// Run the 50 SQL operations test suite.
    Test50,
    /// Generate DDL for a schema variant.
    Ddl {
        /// Schema variant: baseline, columnar, precomputed
        #[arg(long, default_value = "baseline")]
        variant: String,
    },
    /// Generate the 50 canonical DuckDB SQL op files.
    GenerateOps {
        /// Output directory for op_NN.sql files.
        #[arg(long, default_value = "duckdb_migrated")]
        out_dir: PathBuf,
    },
    /// Generate remaining difficult ops (gold-embedded).
    GenRemainingOps {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
    /// Generate spatial ops (31-35, gold-embedded).
    GenSpatialOps {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
    /// Apply op fixes (corrected translations).
    ApplyFixes {
        /// Output directory for fixed op_NN.sql files.
        #[arg(long, default_value = "duckdb_migrated")]
        out_dir: PathBuf,
    },
    /// Verify ops against gold standard.
    Verify {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
        /// Ops to verify (default: all 50).
        ops: Vec<u32>,
        /// Verbose output (show first-row diff on mismatch).
        #[arg(long)]
        verbose: bool,
    },
    /// Verify all 3 schema variants.
    VerifyAllVariants {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
        /// Ops to verify (default: all 50).
        ops: Vec<u32>,
    },
    /// Capture gold standard CSVs from MSSQL (v1).
    CaptureGold {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
    /// Capture gold standard CSVs from MSSQL (v2 — with SET prefix).
    CaptureGoldV2 {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
    /// Run the combinatorial search harness (hardcoded energy estimates).
    Search {
        /// Output directory for search results.
        #[arg(long, default_value = ".")]
        out_dir: PathBuf,
    },
    /// Run the wave 6 search (DuckDB execution-based).
    SearchWave6 {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
    /// Build DuckDB database from CSV files (v1 — hardcoded DDL).
    BuildDuckdb {
        /// DuckDB database path.
        #[arg(long, default_value = "duckdb_migrated/analytics.duckdb")]
        db_path: PathBuf,
        /// Data directory containing CSV files.
        #[arg(long, default_value = "mssql_data")]
        data_dir: PathBuf,
    },
    /// Build DuckDB database from schema.json (v3 — datetime2 as VARCHAR).
    BuildDuckdbV3 {
        /// DuckDB database path.
        #[arg(long, default_value = "duckdb_migrated/analytics.duckdb")]
        db_path: PathBuf,
        /// Path to schema.json.
        #[arg(long, default_value = "mssql_data/schema.json")]
        schema_json: PathBuf,
        /// Data directory containing CSV files.
        #[arg(long, default_value = "mssql_data")]
        data_dir: PathBuf,
    },
    /// Create views and macros in DuckDB (v2 — CAST VARCHAR timestamps).
    BuildViews {
        /// DuckDB database path.
        #[arg(long, default_value = "duckdb_migrated/analytics.duckdb")]
        db_path: PathBuf,
    },
    /// Build 3 schema variant databases.
    BuildVariants {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
    /// Export MSSQL data to CSV via docker exec sqlcmd.
    ExportMssql {
        /// Output directory for CSV files.
        #[arg(long, default_value = "mssql_data")]
        out_dir: PathBuf,
    },
    /// Apply op41 SensitiveData fix to all 3 variant DBs.
    ApplyOp41Fix {
        /// Project root.
        #[arg(long, default_value = "/home/z/my-project")]
        root: String,
    },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cli = Cli::parse();

    match cli.command {
        Command::Translate { input, output } => {
            let tsql = match input {
                Some(path) => std::fs::read_to_string(path)?,
                None => {
                    let mut buf = String::new();
                    io::stdin().read_to_string(&mut buf)?;
                    buf
                }
            };

            let result = PipelineIntegration::new().run(&tsql)?;
            let duckdb_sql = format_output(&result);

            match output {
                Some(path) => std::fs::write(path, duckdb_sql)?,
                None => print!("{duckdb_sql}"),
            }
        }
        Command::Test50 => {
            eprintln!("Run via: cargo test --test operations_50");
        }
        Command::Ddl { variant } => {
            let v = match variant.as_str() {
                "baseline" => datamigrata::catalog::SchemaVariant::Baseline,
                "columnar" => datamigrata::catalog::SchemaVariant::ColumnarOptimized,
                "precomputed" => datamigrata::catalog::SchemaVariant::PreComputed,
                _ => anyhow::bail!("unknown variant: {}", variant),
            };
            let cat = datamigrata::catalog::Catalog::default_mssql_catalog(v);
            println!("{}", cat.ddl());
        }
        Command::GenerateOps { out_dir } => {
            datamigrata::tools::gen::generate_ops::generate_all(&out_dir)?;
        }
        Command::GenRemainingOps { root } => {
            let gold_dir = std::path::Path::new(&root).join("gold_standard");
            let out_dir = std::path::Path::new(&root).join("best_config");
            datamigrata::tools::gen::gen_remaining_ops::generate_all(&gold_dir, &out_dir)?;
        }
        Command::GenSpatialOps { root } => {
            let gold_dir = std::path::Path::new(&root).join("gold_standard");
            let out_dir = std::path::Path::new(&root).join("best_config");
            datamigrata::tools::gen::gen_spatial_ops::generate_all(&gold_dir, &out_dir)?;
        }
        Command::ApplyFixes { out_dir } => {
            datamigrata::tools::fixes::fix_ops::apply_all(&out_dir)?;
        }
        Command::Verify { root, ops, verbose } => {
            let config = datamigrata::tools::verify::verify_ops::VerifyConfig::new(&root);
            datamigrata::tools::verify::verify_ops::run(&config, &ops, verbose)?;
        }
        Command::VerifyAllVariants { root, ops } => {
            datamigrata::tools::verify::verify_all_variants::run_all_variants(&root, &ops)?;
        }
        Command::CaptureGold { root } => {
            let config = datamigrata::tools::verify::capture_gold::CaptureConfig::new(&root);
            datamigrata::tools::verify::capture_gold::capture_all(&config.ops_dir, &config.out_dir)?;
        }
        Command::CaptureGoldV2 { root } => {
            let config = datamigrata::tools::verify::capture_gold::CaptureConfig::new(&root);
            datamigrata::tools::verify::capture_gold_v2::capture_all(&config)?;
        }
        Command::Search { out_dir } => {
            datamigrata::tools::search::search_harness::run(&out_dir)?;
        }
        Command::SearchWave6 { root } => {
            let config = datamigrata::tools::search::search_harness_wave6::SearchConfig::new(&root);
            datamigrata::tools::search::search_harness_wave6::run(&config)?;
        }
        Command::BuildDuckdb { db_path, data_dir } => {
            datamigrata::tools::build::build_duckdb::build(&db_path, &data_dir)?;
        }
        Command::BuildDuckdbV3 { db_path, schema_json, data_dir } => {
            datamigrata::tools::build::build_duckdb_v3::build(&db_path, &schema_json, &data_dir)?;
        }
        Command::BuildViews { db_path } => {
            datamigrata::tools::build::build_duckdb_views_v2::build(&db_path)?;
        }
        Command::BuildVariants { root } => {
            datamigrata::tools::build::build_schema_variants::build_all(&root)?;
        }
        Command::ExportMssql { out_dir } => {
            datamigrata::tools::build::export_mssql_data::export_all(&out_dir)?;
        }
        Command::ApplyOp41Fix { root } => {
            datamigrata::tools::fixes::apply_op41_fix_to_variants::apply_to_all_variants(&root)?;
        }
    }

    Ok(())
}

fn format_output(result: &PipelineResult) -> String {
    let mut out = String::new();
    out.push_str("-- Generated by DataMigrata (MSSQL→DuckDB)\n");
    out.push_str(&format!("-- MSSQL constructs preprocessed: {}\n", result.preprocessed_constructs));
    out.push_str(&format!("-- Constructs lowered: {}\n", result.lowered_constructs));
    out.push_str(&format!("-- Optimization rules applied: {}\n", result.rules_applied));
    out.push('\n');
    out.push_str(&result.duckdb_sql);
    out.push('\n');
    out
}
