use std::str::FromStr;
use std::time::Duration;

use async_trait::async_trait;
use sqlx_core::connection::{ConnectOptions, Connection};
use sqlx_postgres::{PgConnectOptions, PgConnection, PgSslMode, Postgres};
use time::PrimitiveDateTime;

use super::{ApiKeyRow, MerchantRow, SourceRows, SyncSource};

// Rows already expired are left out, so the sync deletes them from the table
const API_KEYS_SQL: &str = "SELECT hashed_api_key, merchant_id, expires_at FROM api_keys \
     WHERE expires_at IS NULL OR expires_at > (now() AT TIME ZONE 'UTC')";
const MERCHANTS_SQL: &str = "SELECT merchant_id, publishable_key FROM merchant_account";

pub struct PostgresSource {
    options: PgConnectOptions,
}

impl PostgresSource {
    pub fn new(url: &str, root_cert: Option<&str>, timeout: Duration) -> anyhow::Result<Self> {
        let mut options = PgConnectOptions::from_str(url)
            .map_err(|_| anyhow::anyhow!("database url is invalid"))?
            .options([
                ("default_transaction_read_only", "on"),
                ("statement_timeout", &timeout.as_millis().to_string()),
            ]);
        // TLS with a verified server name unless the URL sets sslmode itself (local runs)
        if !url.contains("sslmode=") {
            options = options.ssl_mode(PgSslMode::VerifyFull);
        }
        if let Some(path) = root_cert {
            options = options.ssl_root_cert(path);
        }
        Ok(Self { options })
    }
}

#[async_trait]
impl SyncSource for PostgresSource {
    async fn load(&self) -> anyhow::Result<SourceRows> {
        let mut conn: PgConnection = self.options.connect().await?;
        let mut tx = conn.begin().await?;
        // One snapshot for both reads, so a merchant and its keys come from the same moment
        sqlx_core::query::query::<Postgres>(
            "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY",
        )
        .execute(&mut *tx)
        .await?;
        let api_keys = sqlx_core::query_as::query_as::<
            Postgres,
            (String, String, Option<PrimitiveDateTime>),
        >(API_KEYS_SQL)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .map(|(hashed_api_key, merchant_id, expires_at)| ApiKeyRow {
            hashed_api_key,
            merchant_id,
            expires_at: expires_at.map(|t| t.assume_utc().unix_timestamp()),
        })
        .collect();
        let merchants =
            sqlx_core::query_as::query_as::<Postgres, (String, Option<String>)>(MERCHANTS_SQL)
                .fetch_all(&mut *tx)
                .await?
                .into_iter()
                .map(|(merchant_id, publishable_key)| MerchantRow {
                    merchant_id,
                    publishable_key,
                })
                .collect();
        tx.commit().await?;
        conn.close().await?;
        Ok(SourceRows {
            api_keys,
            merchants,
        })
    }
}
