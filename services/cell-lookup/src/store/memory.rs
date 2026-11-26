use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;

use async_trait::async_trait;

use super::{Item, RouteStore, StoreError};
use crate::lookup::hash::LookupKey;

// In-memory route table with an outage switch and call counters, for tests and local runs
#[derive(Default)]
pub struct MemoryStore {
    items: Mutex<BTreeMap<LookupKey, super::Route>>,
    down: AtomicBool,
    pub scans: AtomicUsize,
    pub gets: AtomicUsize,
}

impl MemoryStore {
    pub fn with_items(items: Vec<Item>) -> Self {
        let store = Self::default();
        store.lock().extend(items);
        store
    }

    pub fn set_down(&self, down: bool) {
        self.down.store(down, Ordering::SeqCst);
    }

    pub fn insert(&self, key: LookupKey, route: super::Route) {
        self.lock().insert(key, route);
    }

    pub fn remove(&self, key: &LookupKey) {
        self.lock().remove(key);
    }

    pub fn len(&self) -> usize {
        self.lock().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn snapshot(&self) -> Vec<Item> {
        self.lock()
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, BTreeMap<LookupKey, super::Route>> {
        self.items.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn check(&self, op: &'static str) -> Result<(), StoreError> {
        if self.down.load(Ordering::SeqCst) {
            return Err(StoreError::Transport {
                op,
                reason: "table unreachable".into(),
            });
        }
        Ok(())
    }
}

#[async_trait]
impl RouteStore for MemoryStore {
    async fn scan_all(&self) -> Result<Vec<Item>, StoreError> {
        self.scans.fetch_add(1, Ordering::SeqCst);
        self.check("Scan")?;
        Ok(self.snapshot())
    }

    async fn get_many(&self, keys: &[LookupKey]) -> Result<Vec<Item>, StoreError> {
        self.gets.fetch_add(1, Ordering::SeqCst);
        self.check("BatchGetItem")?;
        let items = self.lock();
        Ok(keys
            .iter()
            .filter_map(|k| items.get(k).map(|r| (k.clone(), r.clone())))
            .collect())
    }

    async fn list_cell(&self, cell: &str) -> Result<Vec<Item>, StoreError> {
        self.check("Query")?;
        Ok(self
            .snapshot()
            .into_iter()
            .filter(|(_, r)| r.cell == cell)
            .collect())
    }

    async fn put_many(&self, items: &[Item]) -> Result<(), StoreError> {
        self.check("BatchWriteItem")?;
        self.lock().extend(items.iter().cloned());
        Ok(())
    }

    async fn delete_many(&self, keys: &[LookupKey]) -> Result<(), StoreError> {
        self.check("BatchWriteItem")?;
        let mut items = self.lock();
        for k in keys {
            items.remove(k);
        }
        Ok(())
    }
}
