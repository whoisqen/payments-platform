pub mod plan;
pub mod postgres;

use std::collections::HashSet;

use async_trait::async_trait;

use crate::lookup::credential::valid_merchant_id;
use crate::lookup::hash::{HashKey, LookupKey};
use crate::store::{Item, Kind, Route, RouteStore};

pub use plan::{Limits, PlanError};

pub struct ApiKeyRow {
    pub hashed_api_key: String,
    pub merchant_id: String,
    pub expires_at: Option<i64>,
}

pub struct MerchantRow {
    pub merchant_id: String,
    pub publishable_key: Option<String>,
}

pub struct SourceRows {
    pub api_keys: Vec<ApiKeyRow>,
    pub merchants: Vec<MerchantRow>,
}

// The cell's database, read through its read-only user
#[async_trait]
pub trait SyncSource: Send + Sync {
    async fn load(&self) -> anyhow::Result<SourceRows>;
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Summary {
    pub desired: usize,
    pub puts: usize,
    pub deletes: usize,
    pub skipped: usize,
    pub foreign: usize,
}

fn is_hex_hash(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

// Publishable keys are stored in plaintext by Hyperswitch; only their keyed hash leaves the cell
pub fn desired_items(cell: &str, key: &HashKey, rows: SourceRows) -> (Vec<Item>, usize) {
    let mut skipped = 0;
    let mut items = Vec::new();
    let route = |merchant_id: &str, kind, expires_at| Route {
        cell: cell.to_owned(),
        merchant_id: merchant_id.to_owned(),
        kind,
        expires_at,
    };
    for row in rows.api_keys {
        if !is_hex_hash(&row.hashed_api_key) || !valid_merchant_id(&row.merchant_id) {
            skipped += 1;
            continue;
        }
        items.push((
            LookupKey::hashed(&row.hashed_api_key),
            route(&row.merchant_id, Kind::ApiKey, row.expires_at),
        ));
    }
    for row in rows.merchants {
        if !valid_merchant_id(&row.merchant_id) {
            skipped += 1;
            continue;
        }
        items.push((
            LookupKey::merchant(&row.merchant_id),
            route(&row.merchant_id, Kind::Merchant, None),
        ));
        if let Some(pk) = row.publishable_key.filter(|p| !p.is_empty()) {
            items.push((
                LookupKey::hashed(&key.keyed_hash(&pk)),
                route(&row.merchant_id, Kind::PublishableKey, None),
            ));
        }
    }
    items.sort_by(|a, b| a.0.cmp(&b.0));
    items.dedup_by(|a, b| a.0 == b.0);
    (items, skipped)
}

pub async fn run(
    cell: &str,
    key: &HashKey,
    source: &dyn SyncSource,
    store: &dyn RouteStore,
    limits: Limits,
    dry_run: bool,
) -> anyhow::Result<Summary> {
    let (desired, skipped) = desired_items(cell, key, source.load().await?);
    let existing = store.list_cell(cell).await?;
    let merchant_keys: Vec<LookupKey> = desired
        .iter()
        .map(|(k, _)| k.clone())
        .filter(LookupKey::is_merchant)
        .collect();
    // A merchant another cell already holds (a move in progress) is left alone, not taken over
    let foreign: HashSet<LookupKey> = store
        .get_many(&merchant_keys)
        .await?
        .into_iter()
        .filter(|(_, r)| r.cell != cell)
        .map(|(k, _)| k)
        .collect();
    let desired: Vec<Item> = desired
        .into_iter()
        .filter(|(k, _)| !foreign.contains(k))
        .collect();
    let n = desired.len();
    let p = plan::plan(desired, existing, limits)?;
    let summary = Summary {
        desired: n,
        puts: p.puts.len(),
        deletes: p.deletes.len(),
        skipped,
        foreign: foreign.len(),
    };
    if !dry_run {
        store.put_many(&p.puts).await?;
        store.delete_many(&p.deletes).await?;
    }
    Ok(summary)
}
