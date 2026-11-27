use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use tokio::net::TcpListener;

use cell_lookup::config::{cell_keys, hash_key, Cli, Command, ServeArgs, SyncArgs};
use cell_lookup::lookup::cache::{CacheConfig, RouteCache};
use cell_lookup::lookup::path::PathRules;
use cell_lookup::lookup::Resolver;
use cell_lookup::metrics::Metrics;
use cell_lookup::server::{admin_router, authz_router, App};
use cell_lookup::store::dynamodb::DynamoStore;
use cell_lookup::sync::postgres::PostgresSource;
use cell_lookup::sync::{self, Limits};

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    cell_lookup::telemetry::init();
    match Cli::parse().command {
        Command::Serve(args) => serve(args).await,
        Command::Sync(args) => run_sync(args).await,
    }
}

async fn serve(args: ServeArgs) -> anyhow::Result<()> {
    let keys = cell_keys(&args.cells, env)?;
    let paths = match &args.path_rules {
        Some(rules) => PathRules::parse(rules)?,
        None => PathRules::defaults(),
    };
    let metrics = Arc::new(Metrics::new()?);
    let store = Arc::new(DynamoStore::from_env(args.table.dynamo()).await?);
    let cfg = CacheConfig {
        positive_ttl: Duration::from_secs(args.positive_ttl_seconds),
        negative_ttl: Duration::from_secs(args.negative_ttl_seconds),
        max_entries: args.max_cache_entries,
        miss_concurrency: args.miss_concurrency,
    };
    let cache = Arc::new(RouteCache::new(store, cfg, metrics.clone()));
    tokio::spawn(
        cache
            .clone()
            .refresh_forever(Duration::from_secs(args.refresh_seconds.max(1))),
    );
    let preflight_cell = args
        .preflight_cell
        .clone()
        .or_else(|| args.cells.first().cloned())
        .unwrap_or_default();
    let app = App {
        resolver: Arc::new(Resolver::new(cache, keys, paths)),
        metrics,
        preflight_cell,
    };
    let authz = TcpListener::bind(args.listen).await?;
    let admin = TcpListener::bind(args.admin_listen).await?;
    tracing::info!(listen = %args.listen, admin = %args.admin_listen, cells = args.cells.len(), "serving");
    let authz = axum::serve(authz, authz_router(app.clone())).with_graceful_shutdown(shutdown());
    let admin = axum::serve(admin, admin_router(app)).with_graceful_shutdown(shutdown());
    tokio::try_join!(async { authz.await }, async { admin.await })?;
    Ok(())
}

async fn run_sync(args: SyncArgs) -> anyhow::Result<()> {
    let key = hash_key(&args.cell, env)?;
    let url = env(&args.database_url_env)
        .ok_or_else(|| anyhow::anyhow!("{} is not set", args.database_url_env))?;
    let source = PostgresSource::new(
        &url,
        args.db_root_cert.as_deref(),
        Duration::from_secs(args.db_timeout_seconds),
    )?;
    let store = DynamoStore::from_env(args.table.dynamo()).await?;
    let limits = Limits {
        max_delete_ratio: args.max_delete_ratio,
        min_deletes: args.min_deletes,
        force: args.force,
    };
    match sync::run(&args.cell, &key, &source, &store, limits, args.dry_run).await {
        Ok(s) => {
            tracing::info!(cell = %args.cell, desired = s.desired, puts = s.puts, deletes = s.deletes, skipped = s.skipped, foreign = s.foreign, dry_run = args.dry_run, "sync done");
            Ok(())
        }
        Err(e) => {
            tracing::error!(cell = %args.cell, error = %e, "sync failed");
            Err(e)
        }
    }
}

async fn shutdown() {
    let term = async {
        if let Ok(mut s) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            s.recv().await;
        }
    };
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {}
        _ = term => {}
    }
}
