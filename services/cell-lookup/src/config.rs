use std::net::SocketAddr;
use std::time::Duration;

use clap::{Args, Parser, Subcommand};

use crate::lookup::hash::{CellKey, CellKeys, HashKey};

#[derive(Parser)]
#[command(
    name = "cell-lookup",
    version,
    about = "Edge cell lookup: ext_authz server and table sync"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    Serve(ServeArgs),
    Sync(SyncArgs),
}

#[derive(Args, Clone)]
pub struct TableArgs {
    #[arg(long, env = "CELL_LOOKUP_TABLE")]
    pub table: String,
    #[arg(long, env = "CELL_LOOKUP_CELL_INDEX", default_value = "by-cell")]
    pub cell_index: String,
    #[arg(long, env = "CELL_LOOKUP_DYNAMODB_ENDPOINT")]
    pub dynamodb_endpoint: Option<String>,
    #[arg(long, env = "CELL_LOOKUP_DYNAMODB_TIMEOUT_MS", default_value_t = 2000)]
    pub dynamodb_timeout_ms: u64,
}

#[derive(Args)]
pub struct ServeArgs {
    #[command(flatten)]
    pub table: TableArgs,
    #[arg(long, env = "CELL_LOOKUP_LISTEN", default_value = "0.0.0.0:9191")]
    pub listen: SocketAddr,
    #[arg(long, env = "CELL_LOOKUP_ADMIN_LISTEN", default_value = "0.0.0.0:9090")]
    pub admin_listen: SocketAddr,
    #[arg(
        long,
        env = "CELL_LOOKUP_CELLS",
        value_delimiter = ',',
        required = true
    )]
    pub cells: Vec<String>,
    #[arg(long, env = "CELL_LOOKUP_REFRESH_SECONDS", default_value_t = 30)]
    pub refresh_seconds: u64,
    #[arg(long, env = "CELL_LOOKUP_POSITIVE_TTL_SECONDS", default_value_t = 60)]
    pub positive_ttl_seconds: u64,
    #[arg(long, env = "CELL_LOOKUP_NEGATIVE_TTL_SECONDS", default_value_t = 10)]
    pub negative_ttl_seconds: u64,
    // Answer for CORS preflights, which carry no credential; the first of --cells when unset
    #[arg(long, env = "CELL_LOOKUP_PREFLIGHT_CELL")]
    pub preflight_cell: Option<String>,
    #[arg(long, env = "CELL_LOOKUP_MISS_CONCURRENCY", default_value_t = 16)]
    pub miss_concurrency: usize,
    #[arg(long, env = "CELL_LOOKUP_MAX_CACHE_ENTRIES", default_value_t = 100_000)]
    pub max_cache_entries: usize,
    // Replaces the built-in list; see README for the pattern syntax
    #[arg(long, env = "CELL_LOOKUP_PATH_RULES", value_delimiter = ',')]
    pub path_rules: Option<Vec<String>>,
}

#[derive(Args)]
pub struct SyncArgs {
    #[command(flatten)]
    pub table: TableArgs,
    #[arg(long, env = "CELL_LOOKUP_CELL")]
    pub cell: String,
    // Postgres URL of the cell's read-only user; read from the environment only
    #[arg(long = "database-url-env", default_value = "CELL_LOOKUP_DATABASE_URL")]
    pub database_url_env: String,
    #[arg(long, env = "CELL_LOOKUP_DB_ROOT_CERT")]
    pub db_root_cert: Option<String>,
    #[arg(long, env = "CELL_LOOKUP_DB_TIMEOUT_SECONDS", default_value_t = 60)]
    pub db_timeout_seconds: u64,
    #[arg(long, env = "CELL_LOOKUP_MAX_DELETE_RATIO", default_value_t = 0.2)]
    pub max_delete_ratio: f64,
    // Deletions always allowed per run, so small cells can still revoke keys
    #[arg(long, env = "CELL_LOOKUP_MIN_DELETES", default_value_t = 10)]
    pub min_deletes: usize,
    #[arg(long)]
    pub force: bool,
    #[arg(long)]
    pub dry_run: bool,
}

impl TableArgs {
    pub fn dynamo(&self) -> crate::store::dynamodb::DynamoConfig {
        crate::store::dynamodb::DynamoConfig {
            table: self.table.clone(),
            cell_index: self.cell_index.clone(),
            endpoint: self.dynamodb_endpoint.clone(),
            timeout: Duration::from_millis(self.dynamodb_timeout_ms),
        }
    }
}

// cell-0 reads CELL_LOOKUP_HASH_KEY_CELL_0, filled from Vault secret/<env>/<cell>/shared/app
pub fn hash_key_var(cell: &str) -> String {
    let suffix: String = cell
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_uppercase()
            } else {
                '_'
            }
        })
        .collect();
    format!("CELL_LOOKUP_HASH_KEY_{suffix}")
}

pub fn hash_key(cell: &str, lookup: impl Fn(&str) -> Option<String>) -> anyhow::Result<HashKey> {
    let var = hash_key_var(cell);
    let hex = lookup(&var).ok_or_else(|| anyhow::anyhow!("{var} is not set"))?;
    Ok(HashKey::from_hex(cell, &hex)?)
}

pub fn cell_keys(
    cells: &[String],
    lookup: impl Fn(&str) -> Option<String>,
) -> anyhow::Result<CellKeys> {
    let keys = cells
        .iter()
        .map(|cell| {
            Ok(CellKey {
                cell: cell.clone(),
                key: hash_key(cell, &lookup)?,
            })
        })
        .collect::<anyhow::Result<Vec<_>>>()?;
    Ok(CellKeys::new(keys))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_key_variable_names() {
        assert_eq!(hash_key_var("cell-0"), "CELL_LOOKUP_HASH_KEY_CELL_0");
        assert_eq!(hash_key_var("spare"), "CELL_LOOKUP_HASH_KEY_SPARE");
    }

    #[test]
    fn missing_key_names_the_variable_only() {
        let err = cell_keys(&["cell-1".into()], |_| None)
            .err()
            .expect("error")
            .to_string();
        assert_eq!(err, "CELL_LOOKUP_HASH_KEY_CELL_1 is not set");
    }

    #[test]
    fn loads_keys_per_cell() {
        let keys = cell_keys(&["cell-0".into(), "cell-1".into()], |_| {
            Some("ab".repeat(32))
        })
        .expect("keys");
        assert_eq!(keys.cells().collect::<Vec<_>>(), vec!["cell-0", "cell-1"]);
    }
}
