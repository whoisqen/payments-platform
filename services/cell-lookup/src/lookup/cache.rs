use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use arc_swap::ArcSwapOption;
use tokio::sync::Semaphore;

use super::hash::{Candidate, LookupKey};
use crate::metrics::Metrics;
use crate::store::{Kind, Route, RouteStore};

#[derive(Clone, Debug)]
pub struct CacheConfig {
    pub positive_ttl: Duration,
    pub negative_ttl: Duration,
    // Bound on remembered misses and fresh hits, so a flood of random keys cannot grow memory
    pub max_entries: usize,
    // Concurrent table reads for keys missing from the snapshot; 0 answers from the snapshot only
    pub miss_concurrency: usize,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            positive_ttl: Duration::from_secs(60),
            negative_ttl: Duration::from_secs(10),
            max_entries: 100_000,
            miss_concurrency: 16,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Lookup {
    Found(Route),
    Unknown,
    Unavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
    Snapshot,
    Fresh,
    Negative,
    Table,
    Skipped,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Snapshot => "snapshot",
            Source::Fresh => "fresh",
            Source::Negative => "negative",
            Source::Table => "table",
            Source::Skipped => "skipped",
        }
    }
}

struct Snapshot {
    entries: HashMap<LookupKey, Route>,
    loaded_at: Instant,
}

struct TimedMap<V>(Mutex<HashMap<LookupKey, (V, Instant)>>);

impl<V: Clone> TimedMap<V> {
    fn new() -> Self {
        Self(Mutex::new(HashMap::new()))
    }

    fn get(&self, key: &LookupKey, ttl: Duration) -> Option<V> {
        let map = self.0.lock().unwrap_or_else(|e| e.into_inner());
        map.get(key)
            .filter(|(_, at)| at.elapsed() < ttl)
            .map(|(v, _)| v.clone())
    }

    fn insert(&self, key: LookupKey, value: V, cap: usize) {
        let mut map = self.0.lock().unwrap_or_else(|e| e.into_inner());
        if map.len() >= cap {
            map.clear();
        }
        map.insert(key, (value, Instant::now()));
    }

    fn clear(&self) {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).clear();
    }
}

pub struct RouteCache {
    store: Arc<dyn RouteStore>,
    cfg: CacheConfig,
    snapshot: ArcSwapOption<Snapshot>,
    fresh: TimedMap<Route>,
    negative: TimedMap<()>,
    miss_slots: Semaphore,
    metrics: Arc<Metrics>,
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

// A hash only counts when the cell whose key produced it is the cell the item names
fn matches(c: &Candidate, r: &Route, now: i64) -> bool {
    let kind_fits = if c.key.is_merchant() {
        r.kind == Kind::Merchant
    } else {
        r.kind != Kind::Merchant && r.cell == c.cell
    };
    kind_fits && !r.expired(now)
}

impl RouteCache {
    pub fn new(store: Arc<dyn RouteStore>, cfg: CacheConfig, metrics: Arc<Metrics>) -> Self {
        let miss_slots = Semaphore::new(cfg.miss_concurrency);
        Self {
            store,
            cfg,
            snapshot: ArcSwapOption::empty(),
            fresh: TimedMap::new(),
            negative: TimedMap::new(),
            miss_slots,
            metrics,
        }
    }

    pub async fn refresh(&self) -> Result<usize, crate::store::StoreError> {
        let items = self.store.scan_all().await?;
        let entries: HashMap<_, _> = items.into_iter().collect();
        let n = entries.len();
        self.snapshot.store(Some(Arc::new(Snapshot {
            entries,
            loaded_at: Instant::now(),
        })));
        // A full snapshot supersedes earlier misses: keys created since then become visible at once
        self.negative.clear();
        self.fresh.clear();
        self.metrics.snapshot_entries.set(n as i64);
        Ok(n)
    }

    pub fn snapshot_age(&self) -> Option<Duration> {
        self.snapshot.load().as_ref().map(|s| s.loaded_at.elapsed())
    }

    // Staleness is alerted on, not used here: all pods going unready together would drop every request
    pub fn ready(&self) -> bool {
        self.snapshot_age().is_some()
    }

    pub async fn lookup(&self, candidates: &[Candidate]) -> (Lookup, Source) {
        let Some(first) = candidates.first() else {
            return (Lookup::Unknown, Source::Skipped);
        };
        let now = now_unix();
        let snapshot = self.snapshot.load_full();
        if let Some(s) = snapshot.as_ref() {
            for c in candidates {
                if let Some(r) = s.entries.get(&c.key).filter(|r| matches(c, r, now)) {
                    return (Lookup::Found(r.clone()), Source::Snapshot);
                }
            }
        }
        for c in candidates {
            if let Some(r) = self
                .fresh
                .get(&c.key, self.cfg.positive_ttl)
                .filter(|r| matches(c, r, now))
            {
                return (Lookup::Found(r), Source::Fresh);
            }
        }
        if self
            .negative
            .get(&first.key, self.cfg.negative_ttl)
            .is_some()
        {
            return (Lookup::Unknown, Source::Negative);
        }
        if self.cfg.miss_concurrency == 0 {
            return match snapshot {
                Some(_) => (Lookup::Unknown, Source::Skipped),
                None => (Lookup::Unavailable, Source::Skipped),
            };
        }
        let Ok(_slot) = self.miss_slots.try_acquire() else {
            return (Lookup::Unavailable, Source::Skipped);
        };
        let keys: Vec<LookupKey> = candidates.iter().map(|c| c.key.clone()).collect();
        let items = match self.store.get_many(&keys).await {
            Ok(items) => items,
            Err(e) => {
                tracing::warn!(error = %e, "route table read failed");
                return (Lookup::Unavailable, Source::Table);
            }
        };
        let found = candidates.iter().find_map(|c| {
            items
                .iter()
                .find(|(k, r)| *k == c.key && matches(c, r, now))
                .map(|(k, r)| (k.clone(), r.clone()))
        });
        match found {
            Some((key, route)) => {
                self.fresh.insert(key, route.clone(), self.cfg.max_entries);
                (Lookup::Found(route), Source::Table)
            }
            None => {
                self.negative
                    .insert(first.key.clone(), (), self.cfg.max_entries);
                (Lookup::Unknown, Source::Table)
            }
        }
    }
}

impl RouteCache {
    // On failure the previous snapshot keeps serving however old it is
    pub async fn refresh_once(&self) -> bool {
        match self.refresh().await {
            Ok(n) => {
                self.metrics.refreshes.with_label_values(&["ok"]).inc();
                tracing::debug!(entries = n, "route snapshot loaded");
                true
            }
            Err(e) => {
                self.metrics.refreshes.with_label_values(&["error"]).inc();
                tracing::warn!(error = %e, "route snapshot load failed");
                false
            }
        }
    }

    pub async fn refresh_forever(self: Arc<Self>, every: Duration) {
        let mut tick = tokio::time::interval(every);
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tick.tick().await;
            self.refresh_once().await;
        }
    }
}
