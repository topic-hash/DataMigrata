//! DataMigrata TDS Server (skeleton)
//!
//! A minimal TDS (Tabular Data Stream) protocol listener that dispatches
//! incoming queries to DuckDB-backed operation handlers.
//!
//! This is a skeleton: it accepts a TCP connection, reads a simple text-based
//! query (op_NN), executes the corresponding best_config/op_NN.sql against the
//! DuckDB database, and returns the result count + energy.
//!
//! Production TDS compliance would require implementing the full TDS protocol
//! (https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/).

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::Path;

const DB_PATH: &str = "/home/z/my-project/duckdb_migrated/analytics.duckdb";
const OPS_DIR: &str = "/home/z/my-project/best_config";

fn handle_client(stream: TcpStream) -> std::io::Result<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut writer = stream;
    let mut line = String::new();

    writer.write_all(b"DataMigrata TDS Server (skeleton)\nSend op_NN to execute operation NN (1-50)\n> ")?;

    loop {
        line.clear();
        let n = reader.read_line(&mut line)?;
        if n == 0 { break; }
        let cmd = line.trim();
        if cmd.is_empty() { continue; }
        if cmd == "quit" || cmd == "exit" { break; }

        let op_num: u32 = match cmd.trim_start_matches("op_").parse() {
            Ok(n) if (1..=50).contains(&n) => n,
            _ => {
                writer.write_all(format!("ERROR: invalid op '{}'. Use op_01 to op_50\n> ", cmd).as_bytes())?;
                continue;
            }
        };

        let sql_path = format!("{}/op_{:02}.sql", OPS_DIR, op_num);
        if !Path::new(&sql_path).exists() {
            writer.write_all(format!("ERROR: {} not found\n> ", sql_path).as_bytes())?;
            continue;
        }

        let sql = std::fs::read_to_string(&sql_path)?;
        match duckdb::Connection::open(DB_PATH) {
            Ok(conn) => {
                let start = std::time::Instant::now();
                match conn.prepare(&sql).and_then(|mut s| s.query([], |rows| {
                    let mut count = 0;
                    while rows.next()?.is_some() { count += 1; }
                    Ok(count)
                })) {
                    Ok(row_count) => {
                        let elapsed_ms = start.elapsed().as_millis();
                        let cpu_joules = elapsed_ms as f64 * 5.0 / 1000.0;
                        writer.write_all(format!(
                            "OK op_{:02}: {} rows, {} ms, {:.4} J\n> ",
                            op_num, row_count, elapsed_ms, cpu_joules
                        ).as_bytes())?;
                    }
                    Err(e) => {
                        writer.write_all(format!("ERROR executing op_{:02}: {}\n> ", op_num, e).as_bytes())?;
                    }
                }
            }
            Err(e) => {
                writer.write_all(format!("ERROR connecting to DuckDB: {}\n> ", e).as_bytes())?;
            }
        }
    }
    Ok(())
}

fn main() -> std::io::Result<()> {
    let addr = "127.0.0.1:1433";
    let listener = TcpListener::bind(addr)?;
    println!("DataMigrata TDS Server listening on {}", addr);
    println!("Database: {}", DB_PATH);
    println!("Ops dir:  {}", OPS_DIR);

    for stream in listener.incoming() {
        match stream {
            Ok(s) => {
                std::thread::spawn(move || {
                    if let Err(e) = handle_client(s) {
                        eprintln!("Client error: {}", e);
                    }
                });
            }
            Err(e) => eprintln!("Accept error: {}", e),
        }
    }
    Ok(())
}
