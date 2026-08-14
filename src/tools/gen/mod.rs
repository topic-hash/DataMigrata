//! GROUP A — SQL generation scripts.
//!
//! Ports of:
//! - `scripts/generate_ops.py` → [`generate_ops`]
//! - `scripts/gen_remaining_ops.py` → [`gen_remaining_ops`]
//! - `scripts/gen_spatial_ops.py` → [`gen_spatial_ops`]
//! - `scripts/split_ops.py` → [`split_ops`] (uses [`super::common::op_splitter`])

pub mod generate_ops;
pub mod gen_remaining_ops;
pub mod gen_spatial_ops;
