//! Pipeline benchmark — measures end-to-end throughput on representative
//! Oracle SQL statements.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use datamigrata::PipelineIntegration;

fn bench_simple_select(c: &mut Criterion) {
    let pipeline = PipelineIntegration::new();
    let sql = "SELECT employee_id, last_name FROM employees WHERE salary > 50000";
    c.bench_function("simple_select", |b| {
        b.iter(|| {
            black_box(pipeline.run(black_box(sql)).unwrap());
        });
    });
}

fn bench_oracle_constructs(c: &mut Criterion) {
    let pipeline = PipelineIntegration::new();
    let sql = "SELECT NVL(name, 'unknown'), SYSDATE FROM DUAL";
    c.bench_function("oracle_constructs", |b| {
        b.iter(|| {
            black_box(pipeline.run(black_box(sql)).unwrap());
        });
    });
}

fn bench_connect_by(c: &mut Criterion) {
    let pipeline = PipelineIntegration::new();
    let sql = "SELECT employee_id, manager_id FROM employees CONNECT BY PRIOR employee_id = manager_id START WITH manager_id IS NULL";
    c.bench_function("connect_by", |b| {
        b.iter(|| {
            black_box(pipeline.run(black_box(sql)).unwrap());
        });
    });
}

criterion_group!(benches, bench_simple_select, bench_oracle_constructs, bench_connect_by);
criterion_main!(benches);
