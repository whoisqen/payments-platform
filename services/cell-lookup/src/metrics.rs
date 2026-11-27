use prometheus::{
    Encoder, Gauge, Histogram, HistogramOpts, IntCounterVec, IntGauge, Opts, Registry, TextEncoder,
};

// Labels are fixed enums only; credentials, hashes and merchant ids never become label values
pub struct Metrics {
    pub registry: Registry,
    pub lookups: IntCounterVec,
    pub lookup_seconds: Histogram,
    pub refreshes: IntCounterVec,
    pub snapshot_entries: IntGauge,
    pub snapshot_age_seconds: Gauge,
}

impl Metrics {
    pub fn new() -> prometheus::Result<Self> {
        let registry = Registry::new_custom(Some("cell_lookup".into()), None)?;
        let lookups = IntCounterVec::new(
            Opts::new(
                "lookups_total",
                "Authorization checks by result and answer source",
            ),
            &["result", "source"],
        )?;
        let lookup_seconds = Histogram::with_opts(
            HistogramOpts::new("lookup_duration_seconds", "Time to answer one check").buckets(
                vec![
                    0.000_025, 0.000_05, 0.000_1, 0.000_25, 0.000_5, 0.001, 0.002_5, 0.005, 0.01,
                    0.025, 0.1,
                ],
            ),
        )?;
        let refreshes = IntCounterVec::new(
            Opts::new("refreshes_total", "Snapshot loads from the route table"),
            &["result"],
        )?;
        let snapshot_entries = IntGauge::new("snapshot_entries", "Items in the loaded snapshot")?;
        let snapshot_age_seconds = Gauge::new(
            "snapshot_age_seconds",
            "Seconds since the last successful snapshot load; -1 before the first",
        )?;
        registry.register(Box::new(lookups.clone()))?;
        registry.register(Box::new(lookup_seconds.clone()))?;
        registry.register(Box::new(refreshes.clone()))?;
        registry.register(Box::new(snapshot_entries.clone()))?;
        registry.register(Box::new(snapshot_age_seconds.clone()))?;
        Ok(Self {
            registry,
            lookups,
            lookup_seconds,
            refreshes,
            snapshot_entries,
            snapshot_age_seconds,
        })
    }

    pub fn render(&self) -> String {
        let mut buf = Vec::new();
        if TextEncoder::new()
            .encode(&self.registry.gather(), &mut buf)
            .is_err()
        {
            return String::new();
        }
        String::from_utf8(buf).unwrap_or_default()
    }
}
