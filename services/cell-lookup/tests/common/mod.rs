#![allow(dead_code)]

use std::sync::Arc;
use std::time::Duration;

use axum::body::Body;
use axum::http::{Request, Response};
use cell_lookup::lookup::cache::{CacheConfig, RouteCache};
use cell_lookup::lookup::hash::{CellKey, CellKeys, HashKey, LookupKey};
use cell_lookup::lookup::path::PathRules;
use cell_lookup::lookup::Resolver;
use cell_lookup::metrics::Metrics;
use cell_lookup::server::{admin_router, authz_router, App};
use cell_lookup::store::memory::MemoryStore;
use cell_lookup::store::{Kind, Route};
use tower::ServiceExt;

pub const DEV_HASH_KEY: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
pub const CELL1_HASH_KEY: &str = "1111111111111111111111111111111111111111111111111111111111111111";
// Plaintext and hash under DEV_HASH_KEY, computed with the vendor Hyperswitch code
pub const SECRET_KEY: &str = "dev_Kq2z8pR4tW6yU1iO3aS5dF7gH9jK0lZx";
pub const SECRET_KEY_HASH: &str =
    "0a6fd41859b1e1736a054936bbabe9f7f3e47a05c955fab68330eff46b39ee59";

pub fn keys() -> CellKeys {
    CellKeys::new(vec![
        CellKey {
            cell: "cell-0".into(),
            key: HashKey::from_hex("cell-0", DEV_HASH_KEY).expect("key"),
        },
        CellKey {
            cell: "cell-1".into(),
            key: HashKey::from_hex("cell-1", CELL1_HASH_KEY).expect("key"),
        },
    ])
}

pub fn route(cell: &str, merchant: &str, kind: Kind, expires_at: Option<i64>) -> Route {
    Route {
        cell: cell.into(),
        merchant_id: merchant.into(),
        kind,
        expires_at,
    }
}

pub fn hashed(cell_hex_key: &str, plaintext: &str) -> LookupKey {
    LookupKey::hashed(
        &HashKey::from_hex("t", cell_hex_key)
            .expect("key")
            .keyed_hash(plaintext),
    )
}

pub struct Harness {
    pub store: Arc<MemoryStore>,
    pub cache: Arc<RouteCache>,
    pub app: App,
}

pub fn harness(store: MemoryStore, cfg: CacheConfig) -> Harness {
    let store = Arc::new(store);
    let metrics = Arc::new(Metrics::new().expect("metrics"));
    let cache = Arc::new(RouteCache::new(store.clone(), cfg, metrics.clone()));
    let resolver = Arc::new(Resolver::new(cache.clone(), keys(), PathRules::defaults()));
    Harness {
        store,
        cache,
        app: App {
            resolver,
            metrics,
            preflight_cell: "cell-0".into(),
        },
    }
}

pub fn short_ttls() -> CacheConfig {
    CacheConfig {
        positive_ttl: Duration::from_millis(200),
        negative_ttl: Duration::from_millis(200),
        ..CacheConfig::default()
    }
}

pub async fn check(app: &App, path: &str, headers: &[(&str, &str)]) -> Response<Body> {
    let mut req = Request::builder().method("POST").uri(path);
    for (k, v) in headers {
        req = req.header(*k, *v);
    }
    authz_router(app.clone())
        .oneshot(req.body(Body::empty()).expect("request"))
        .await
        .expect("response")
}

pub async fn options(app: &App, path: &str) -> Response<Body> {
    let req = Request::builder()
        .method("OPTIONS")
        .uri(path)
        .header("access-control-request-headers", "api-key")
        .body(Body::empty())
        .expect("request");
    authz_router(app.clone())
        .oneshot(req)
        .await
        .expect("response")
}

pub async fn admin(app: &App, path: &str) -> Response<Body> {
    admin_router(app.clone())
        .oneshot(Request::get(path).body(Body::empty()).expect("request"))
        .await
        .expect("response")
}

pub fn header<'a>(resp: &'a Response<Body>, name: &str) -> Option<&'a str> {
    resp.headers().get(name).and_then(|v| v.to_str().ok())
}
