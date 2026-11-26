mod common;

use async_trait::async_trait;
use cell_lookup::lookup::hash::{HashKey, LookupKey};
use cell_lookup::store::memory::MemoryStore;
use cell_lookup::store::Kind;
use cell_lookup::sync::{self, ApiKeyRow, Limits, MerchantRow, PlanError, SourceRows, SyncSource};
use common::*;

struct FakeDb {
    keys: Vec<(&'static str, &'static str, Option<i64>)>,
    merchants: Vec<(&'static str, Option<&'static str>)>,
}

#[async_trait]
impl SyncSource for FakeDb {
    async fn load(&self) -> anyhow::Result<SourceRows> {
        Ok(SourceRows {
            api_keys: self
                .keys
                .iter()
                .map(|(h, m, e)| ApiKeyRow {
                    hashed_api_key: (*h).into(),
                    merchant_id: (*m).into(),
                    expires_at: *e,
                })
                .collect(),
            merchants: self
                .merchants
                .iter()
                .map(|(m, pk)| MerchantRow {
                    merchant_id: (*m).into(),
                    publishable_key: pk.map(Into::into),
                })
                .collect(),
        })
    }
}

const LIMITS: Limits = Limits {
    max_delete_ratio: 0.5,
    min_deletes: 0,
    force: false,
};

fn key() -> HashKey {
    HashKey::from_hex("cell-0", DEV_HASH_KEY).expect("key")
}

fn other_cell_item() -> (LookupKey, cell_lookup::store::Route) {
    (
        LookupKey::merchant("merchant_z"),
        route("cell-1", "merchant_z", Kind::Merchant, None),
    )
}

#[tokio::test]
async fn first_sync_writes_keys_merchants_and_hashed_publishable_keys() {
    let store = MemoryStore::with_items(vec![other_cell_item()]);
    let db = FakeDb {
        keys: vec![
            (SECRET_KEY_HASH, "merchant_a", Some(1_900_000_000)),
            ("not-a-hash", "merchant_a", None),
        ],
        merchants: vec![("merchant_a", Some("pk_dev_a"))],
    };
    let s = sync::run("cell-0", &key(), &db, &store, LIMITS, false)
        .await
        .expect("sync");
    assert_eq!((s.desired, s.puts, s.deletes, s.skipped), (3, 3, 0, 1));
    let items = store.snapshot();
    assert!(items
        .iter()
        .any(|(k, r)| *k == LookupKey::hashed(SECRET_KEY_HASH)
            && r.expires_at == Some(1_900_000_000)));
    assert!(items
        .iter()
        .any(|(k, r)| *k == hashed(DEV_HASH_KEY, "pk_dev_a") && r.kind == Kind::PublishableKey));
    assert!(!items.iter().any(|(k, _)| k.as_str().contains("pk_dev_a")));
}

#[tokio::test]
async fn revoked_key_is_deleted_and_other_cells_are_untouched() {
    let store = MemoryStore::with_items(vec![other_cell_item()]);
    let full = FakeDb {
        keys: vec![(SECRET_KEY_HASH, "merchant_a", None)],
        merchants: vec![("merchant_a", None), ("merchant_c", None)],
    };
    sync::run("cell-0", &key(), &full, &store, LIMITS, false)
        .await
        .expect("sync");
    let revoked = FakeDb {
        keys: vec![],
        merchants: vec![("merchant_a", None), ("merchant_c", None)],
    };
    let s = sync::run("cell-0", &key(), &revoked, &store, LIMITS, false)
        .await
        .expect("sync");
    assert_eq!((s.puts, s.deletes), (0, 1));
    assert_eq!(store.len(), 3);
    assert!(store.snapshot().contains(&other_cell_item()));
}

#[tokio::test]
async fn empty_source_is_refused() {
    let store = MemoryStore::with_items(vec![(
        LookupKey::merchant("merchant_a"),
        route("cell-0", "merchant_a", Kind::Merchant, None),
    )]);
    let db = FakeDb {
        keys: vec![],
        merchants: vec![],
    };
    let err = sync::run("cell-0", &key(), &db, &store, LIMITS, false)
        .await
        .expect_err("refused");
    assert_eq!(
        err.downcast_ref::<PlanError>(),
        Some(&PlanError::EmptySource(1))
    );
    assert_eq!(store.len(), 1);
}

#[tokio::test]
async fn merchant_owned_by_another_cell_is_skipped_not_taken() {
    let store = MemoryStore::with_items(vec![other_cell_item()]);
    let db = FakeDb {
        keys: vec![(SECRET_KEY_HASH, "merchant_a", None)],
        merchants: vec![("merchant_z", None)],
    };
    let s = sync::run("cell-0", &key(), &db, &store, LIMITS, false)
        .await
        .expect("sync");
    assert_eq!((s.foreign, s.puts), (1, 1));
    assert!(store.snapshot().contains(&other_cell_item()));
}

#[tokio::test]
async fn dry_run_writes_nothing() {
    let store = MemoryStore::default();
    let db = FakeDb {
        keys: vec![(SECRET_KEY_HASH, "merchant_a", None)],
        merchants: vec![],
    };
    let s = sync::run("cell-0", &key(), &db, &store, LIMITS, true)
        .await
        .expect("sync");
    assert_eq!(s.puts, 1);
    assert!(store.is_empty());
}

#[tokio::test]
async fn table_outage_fails_the_run() {
    let store = MemoryStore::default();
    store.set_down(true);
    let db = FakeDb {
        keys: vec![(SECRET_KEY_HASH, "merchant_a", None)],
        merchants: vec![],
    };
    assert!(sync::run("cell-0", &key(), &db, &store, LIMITS, false)
        .await
        .is_err());
}
