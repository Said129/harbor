//! Desktop 0.9.132 public catalog. Provider parsing and pagination retain upstream sources.
include!("types.rs");
pub mod connector;
pub mod model;
pub use model::*;
pub mod connectors {
    pub mod catalog;
    pub mod jellyfin;
    pub mod plex;
}
mod request;
pub(crate) use request::{execute, Request};

#[derive(Clone, Copy, Default)]
pub struct CatalogContext;
