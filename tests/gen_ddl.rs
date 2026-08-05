use datamigrata::catalog::{Catalog, SchemaVariant};
use std::fs;

#[test]
fn generate_all_ddl() {
    for variant in SchemaVariant::all() {
        let cat = Catalog::default_mssql_catalog(*variant);
        let ddl = cat.ddl();
        let filename = format!("schema_variants/{}.sql", variant.name());
        fs::write(&filename, &ddl).unwrap();
        println!("Generated {} ({} bytes)", filename, ddl.len());
    }
}
