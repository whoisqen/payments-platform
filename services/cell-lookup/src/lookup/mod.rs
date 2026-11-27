pub mod cache;
pub mod credential;
pub mod hash;
pub mod path;

use std::sync::Arc;

use axum::http::HeaderMap;

use self::cache::{Lookup, RouteCache, Source};
use self::credential::Credential;
use self::hash::{Candidate, CellKeys, LookupKey};
use self::path::PathRules;
use crate::store::Route;

#[derive(Debug, PartialEq, Eq)]
pub enum Decision {
    Route(Route),
    // A credential was presented and no cell holds it
    UnknownCredential,
    // Nothing on the request names a merchant
    NoRoute,
    // The table cannot be read and the cache cannot answer
    Unavailable,
}

impl Decision {
    pub fn label(&self) -> &'static str {
        match self {
            Decision::Route(_) => "found",
            Decision::UnknownCredential => "unknown",
            Decision::NoRoute => "no_route",
            Decision::Unavailable => "unavailable",
        }
    }
}

pub struct Resolver {
    pub cache: Arc<RouteCache>,
    keys: CellKeys,
    paths: PathRules,
}

impl Resolver {
    pub fn new(cache: Arc<RouteCache>, keys: CellKeys, paths: PathRules) -> Self {
        Self { cache, keys, paths }
    }

    // A credential the table knows decides; otherwise a merchant id from the path, x-merchant-id or a JWT
    pub async fn resolve(&self, headers: &HeaderMap, path: &str) -> (Decision, Source) {
        let credential = credential::extract(headers);
        if let Credential::Key(key) = &credential {
            let (found, source) = self.cache.lookup(&self.keys.candidates(key)).await;
            match found {
                Lookup::Found(route) => return (Decision::Route(route), source),
                Lookup::Unavailable => return (Decision::Unavailable, source),
                Lookup::Unknown => {}
            }
        }
        let merchant = self
            .paths
            .merchant_of(path)
            .or_else(|| credential::merchant_header(headers))
            .map(str::to_owned)
            .or(match &credential {
                Credential::Jwt { merchant_id } => Some(merchant_id.clone()),
                _ => None,
            });
        let Some(merchant_id) = merchant else {
            return match credential {
                Credential::Key(_) | Credential::Ephemeral => {
                    (Decision::UnknownCredential, Source::Skipped)
                }
                _ => (Decision::NoRoute, Source::Skipped),
            };
        };
        let candidate = Candidate {
            cell: String::new(),
            key: LookupKey::merchant(&merchant_id),
        };
        match self.cache.lookup(std::slice::from_ref(&candidate)).await {
            (Lookup::Found(route), source) => (Decision::Route(route), source),
            (Lookup::Unavailable, source) => (Decision::Unavailable, source),
            (Lookup::Unknown, source) => match credential {
                Credential::None => (Decision::NoRoute, source),
                _ => (Decision::UnknownCredential, source),
            },
        }
    }
}
