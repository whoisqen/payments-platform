mod common;

use std::sync::atomic::Ordering;
use std::time::Duration;

use axum::http::StatusCode;
use cell_lookup::lookup::cache::CacheConfig;
use cell_lookup::lookup::hash::LookupKey;
use cell_lookup::store::memory::MemoryStore;
use cell_lookup::store::Kind;
use common::*;

fn seeded() -> MemoryStore {
    MemoryStore::with_items(vec![
        (
            LookupKey::hashed(SECRET_KEY_HASH),
            route("cell-0", "merchant_a", Kind::ApiKey, None),
        ),
        (
            hashed(CELL1_HASH_KEY, "pk_dev_cell1"),
            route("cell-1", "merchant_b", Kind::PublishableKey, None),
        ),
        (
            LookupKey::merchant("merchant_b"),
            route("cell-1", "merchant_b", Kind::Merchant, None),
        ),
        (
            hashed(DEV_HASH_KEY, "dev_expired"),
            route("cell-0", "merchant_a", Kind::ApiKey, Some(1)),
        ),
        // Hash made with cell-0's key but filed under cell-1: must never route
        (
            hashed(DEV_HASH_KEY, "dev_misfiled"),
            route("cell-1", "merchant_a", Kind::ApiKey, None),
        ),
    ])
}

#[tokio::test]
async fn vendor_hashed_key_routes_to_its_cell() {
    let h = harness(seeded(), CacheConfig::default());
    assert!(h.cache.refresh_once().await);
    let resp = check(&h.app, "/payments", &[("api-key", SECRET_KEY)]).await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(header(&resp, "x-payments-cell"), Some("cell-0"));
    assert_eq!(header(&resp, "x-merchant-id"), Some("merchant_a"));
}

#[tokio::test]
async fn client_merchant_header_is_left_alone() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    let resp = check(
        &h.app,
        "/payments",
        &[("api-key", SECRET_KEY), ("x-merchant-id", "connected_1")],
    )
    .await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(header(&resp, "x-merchant-id"), None);
}

#[tokio::test]
async fn publishable_key_in_authorization_routes_with_its_cell_key() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    let resp = check(
        &h.app,
        "/payments/pay_1/confirm",
        &[(
            "authorization",
            "publishable-key=pk_dev_cell1,client-secret=x",
        )],
    )
    .await;
    assert_eq!(header(&resp, "x-payments-cell"), Some("cell-1"));
}

#[tokio::test]
async fn unknown_expired_and_misfiled_keys_are_refused() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    for key in ["dev_nobody", "dev_expired", "dev_misfiled"] {
        let resp = check(&h.app, "/payments", &[("api-key", key)]).await;
        assert_eq!(resp.status(), StatusCode::FORBIDDEN, "{key}");
        assert_eq!(header(&resp, "x-payments-cell"), None);
    }
}

#[tokio::test]
async fn no_credential_routes_by_webhook_path_or_not_at_all() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    let resp = check(&h.app, "/webhooks/merchant_b/stripe", &[]).await;
    assert_eq!(header(&resp, "x-payments-cell"), Some("cell-1"));
    assert_eq!(
        check(&h.app, "/payments", &[]).await.status(),
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        check(&h.app, "/webhooks/merchant_zz/stripe", &[])
            .await
            .status(),
        StatusCode::NOT_FOUND
    );
}

#[tokio::test]
async fn ephemeral_key_routes_only_by_path() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    let resp = check(
        &h.app,
        "/customers/c1/payment_methods",
        &[("api-key", "epk_1")],
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn health_is_not_answered_on_the_authz_listener() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    assert_eq!(
        check(&h.app, "/healthz", &[]).await.status(),
        StatusCode::NOT_FOUND
    );
    assert_eq!(admin(&h.app, "/healthz").await.status(), StatusCode::OK);
}

#[tokio::test]
async fn outage_with_empty_cache_answers_503_and_not_ready() {
    let store = seeded();
    store.set_down(true);
    let h = harness(store, CacheConfig::default());
    assert!(!h.cache.refresh_once().await);
    let resp = check(&h.app, "/payments", &[("api-key", SECRET_KEY)]).await;
    assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(header(&resp, "retry-after"), Some("1"));
    assert_eq!(
        admin(&h.app, "/readyz").await.status(),
        StatusCode::SERVICE_UNAVAILABLE
    );
}

#[tokio::test]
async fn outage_after_load_serves_the_snapshot() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    h.store.set_down(true);
    assert!(!h.cache.refresh_once().await);
    let resp = check(&h.app, "/payments", &[("api-key", SECRET_KEY)]).await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(admin(&h.app, "/readyz").await.status(), StatusCode::OK);
    assert!(!h.cache.refresh_once().await);
    // A key missing from the snapshot cannot be checked during the outage
    let resp = check(&h.app, "/payments", &[("api-key", "dev_new")]).await;
    assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
}

#[tokio::test]
async fn negative_cache_absorbs_repeats_until_ttl() {
    let h = harness(seeded(), short_ttls());
    h.cache.refresh_once().await;
    for _ in 0..5 {
        check(&h.app, "/payments", &[("api-key", "dev_nobody")]).await;
    }
    assert_eq!(h.store.gets.load(Ordering::SeqCst), 1);
    tokio::time::sleep(Duration::from_millis(250)).await;
    check(&h.app, "/payments", &[("api-key", "dev_nobody")]).await;
    assert_eq!(h.store.gets.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn key_added_after_the_snapshot_is_read_once_then_cached() {
    let h = harness(seeded(), short_ttls());
    h.cache.refresh_once().await;
    h.store.insert(
        hashed(DEV_HASH_KEY, "dev_fresh"),
        route("cell-0", "merchant_a", Kind::ApiKey, None),
    );
    for _ in 0..3 {
        let resp = check(&h.app, "/payments", &[("api-key", "dev_fresh")]).await;
        assert_eq!(header(&resp, "x-payments-cell"), Some("cell-0"));
    }
    assert_eq!(h.store.gets.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn revoked_key_disappears_with_the_next_snapshot() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    h.store.remove(&LookupKey::hashed(SECRET_KEY_HASH));
    assert_eq!(
        check(&h.app, "/payments", &[("api-key", SECRET_KEY)])
            .await
            .status(),
        StatusCode::OK
    );
    h.cache.refresh_once().await;
    assert_eq!(
        check(&h.app, "/payments", &[("api-key", SECRET_KEY)])
            .await
            .status(),
        StatusCode::FORBIDDEN
    );
}

#[tokio::test]
async fn snapshot_only_mode_never_reads_the_table_on_a_miss() {
    let cfg = CacheConfig {
        miss_concurrency: 0,
        ..CacheConfig::default()
    };
    let h = harness(seeded(), cfg);
    h.cache.refresh_once().await;
    let resp = check(&h.app, "/payments", &[("api-key", "dev_nobody")]).await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    assert_eq!(h.store.gets.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn metrics_never_carry_credentials() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    check(&h.app, "/payments", &[("api-key", SECRET_KEY)]).await;
    check(&h.app, "/payments", &[("api-key", "dev_nobody")]).await;
    let resp = admin(&h.app, "/metrics").await;
    let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .expect("body");
    let text = String::from_utf8(body.to_vec()).expect("utf8");
    assert!(text.contains("cell_lookup_lookups_total{result=\"found\",source=\"snapshot\"} 1"));
    assert!(text.contains("cell_lookup_snapshot_entries 5"));
    assert!(
        !text.contains(SECRET_KEY)
            && !text.contains(SECRET_KEY_HASH)
            && !text.contains("merchant_a")
    );
}

#[tokio::test]
async fn cached_lookup_is_well_under_a_millisecond() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    let candidates = keys().candidates(SECRET_KEY);
    let n = 20_000;
    let started = std::time::Instant::now();
    for _ in 0..n {
        h.cache.lookup(&candidates).await;
    }
    let per_lookup = started.elapsed() / n;
    assert!(per_lookup < Duration::from_micros(200), "{per_lookup:?}");
}

#[tokio::test]
async fn cors_preflight_without_credential_is_answered() {
    let h = harness(seeded(), CacheConfig::default());
    let resp = options(&h.app, "/payments").await;
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(header(&resp, "x-payments-cell"), Some("cell-0"));
    assert_eq!(header(&resp, "x-merchant-id"), None);
}

#[tokio::test]
async fn admin_key_routes_by_merchant_header() {
    let h = harness(seeded(), CacheConfig::default());
    h.cache.refresh_once().await;
    let resp = check(
        &h.app,
        "/routing",
        &[("api-key", "admin_key"), ("x-merchant-id", "merchant_b")],
    )
    .await;
    assert_eq!(header(&resp, "x-payments-cell"), Some("cell-1"));
    assert_eq!(header(&resp, "x-merchant-id"), None);
}
