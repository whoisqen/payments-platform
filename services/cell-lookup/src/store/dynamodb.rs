use std::time::{Duration, SystemTime};

use async_trait::async_trait;
use aws_config::BehaviorVersion;
use aws_credential_types::provider::{ProvideCredentials, SharedCredentialsProvider};
use aws_sigv4::http_request::{sign, SignableBody, SignableRequest, SigningSettings};
use aws_sigv4::sign::v4;
use serde_json::{json, Map, Value};

use super::{Item, Kind, Route, RouteStore, StoreError};
use crate::lookup::hash::LookupKey;

const PK: &str = "lookup_key";
const BATCH_GET: usize = 100;
const BATCH_WRITE: usize = 25;
const ATTEMPTS: u32 = 5;

#[derive(Clone)]
pub struct DynamoConfig {
    pub table: String,
    pub cell_index: String,
    // Set for DynamoDB Local or a VPC endpoint; empty means the regional endpoint
    pub endpoint: Option<String>,
    pub timeout: Duration,
}

// Thin signed client for the JSON protocol: aws-sdk-dynamodb is not in the offline registry
pub struct DynamoStore {
    http: reqwest::Client,
    url: String,
    region: String,
    credentials: SharedCredentialsProvider,
    cfg: DynamoConfig,
}

impl DynamoStore {
    pub async fn from_env(cfg: DynamoConfig) -> anyhow::Result<Self> {
        let sdk = aws_config::defaults(BehaviorVersion::latest()).load().await;
        let region = sdk
            .region()
            .map(|r| r.to_string())
            .ok_or_else(|| anyhow::anyhow!("AWS region is not set"))?;
        let credentials = sdk
            .credentials_provider()
            .ok_or_else(|| anyhow::anyhow!("no AWS credentials provider"))?;
        let url = cfg
            .endpoint
            .clone()
            .unwrap_or_else(|| format!("https://dynamodb.{region}.amazonaws.com/"));
        let http = reqwest::Client::builder()
            .timeout(cfg.timeout)
            .pool_idle_timeout(Duration::from_secs(50))
            .build()?;
        Ok(Self {
            http,
            url,
            region,
            credentials,
            cfg,
        })
    }

    async fn call(&self, op: &'static str, body: Value) -> Result<Value, StoreError> {
        let mut delay = Duration::from_millis(50);
        for attempt in 1..=ATTEMPTS {
            match self.call_once(op, &body).await {
                Err(StoreError::Service { kind, status, .. })
                    if attempt < ATTEMPTS && retryable(&kind, status) => {}
                Err(StoreError::Transport { .. }) if attempt < ATTEMPTS => {}
                other => return other,
            }
            tokio::time::sleep(delay).await;
            delay *= 2;
        }
        Err(StoreError::Transport {
            op,
            reason: "retries exhausted".into(),
        })
    }

    async fn call_once(&self, op: &'static str, body: &Value) -> Result<Value, StoreError> {
        let payload = serde_json::to_vec(body).map_err(|e| StoreError::Decode {
            op,
            reason: e.to_string(),
        })?;
        let creds =
            self.credentials
                .provide_credentials()
                .await
                .map_err(|e| StoreError::Credentials {
                    op,
                    reason: e.to_string(),
                })?;
        let identity = creds.into();
        let target = format!("DynamoDB_20120810.{op}");
        let headers = [
            ("content-type", "application/x-amz-json-1.0"),
            ("x-amz-target", target.as_str()),
        ];
        let params = v4::SigningParams::builder()
            .identity(&identity)
            .region(&self.region)
            .name("dynamodb")
            .time(SystemTime::now())
            .settings(SigningSettings::default())
            .build()
            .map_err(|e| StoreError::Credentials {
                op,
                reason: e.to_string(),
            })?
            .into();
        let signable = SignableRequest::new(
            "POST",
            self.url.as_str(),
            headers.iter().copied(),
            SignableBody::Bytes(&payload),
        )
        .map_err(|e| StoreError::Credentials {
            op,
            reason: e.to_string(),
        })?;
        let (instructions, _) = sign(signable, &params)
            .map_err(|e| StoreError::Credentials {
                op,
                reason: e.to_string(),
            })?
            .into_parts();

        let mut req = self.http.post(&self.url).body(payload.clone());
        for (k, v) in headers.iter().copied().chain(instructions.headers()) {
            req = req.header(k, v);
        }
        let resp = req.send().await.map_err(|e| StoreError::Transport {
            op,
            reason: e.without_url().to_string(),
        })?;
        let status = resp.status().as_u16();
        let bytes = resp.bytes().await.map_err(|e| StoreError::Transport {
            op,
            reason: e.without_url().to_string(),
        })?;
        let value: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
        if status >= 300 {
            let kind = value
                .get("__type")
                .and_then(Value::as_str)
                .and_then(|t| t.rsplit('#').next())
                .unwrap_or("unknown")
                .to_owned();
            return Err(StoreError::Service { op, kind, status });
        }
        Ok(value)
    }

    async fn paged(&self, op: &'static str, mut body: Value) -> Result<Vec<Item>, StoreError> {
        let mut out = Vec::new();
        loop {
            let resp = self.call(op, body.clone()).await?;
            for raw in resp
                .get("Items")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                if let Some(item) = decode(raw) {
                    out.push(item);
                }
            }
            match resp.get("LastEvaluatedKey") {
                Some(k) if !k.is_null() => body["ExclusiveStartKey"] = k.clone(),
                _ => return Ok(out),
            }
        }
    }

    async fn write(&self, requests: Vec<Value>) -> Result<(), StoreError> {
        for chunk in requests.chunks(BATCH_WRITE) {
            let mut pending = Value::Array(chunk.to_vec());
            let mut delay = Duration::from_millis(50);
            for attempt in 1..=ATTEMPTS {
                let body = json!({"RequestItems": {self.cfg.table.as_str(): pending}});
                let resp = self.call("BatchWriteItem", body).await?;
                match resp
                    .get("UnprocessedItems")
                    .and_then(|u| u.get(&self.cfg.table))
                {
                    Some(Value::Array(left)) if !left.is_empty() => {
                        if attempt == ATTEMPTS {
                            return Err(StoreError::Service {
                                op: "BatchWriteItem",
                                kind: "UnprocessedItems".into(),
                                status: 200,
                            });
                        }
                        pending = Value::Array(left.clone());
                    }
                    _ => break,
                }
                tokio::time::sleep(delay).await;
                delay *= 2;
            }
        }
        Ok(())
    }
}

fn retryable(kind: &str, status: u16) -> bool {
    status >= 500
        || matches!(
            kind,
            "ProvisionedThroughputExceededException"
                | "ThrottlingException"
                | "RequestLimitExceeded"
                | "LimitExceededException"
        )
}

pub fn encode(key: &LookupKey, route: &Route) -> Value {
    let mut m = Map::new();
    m.insert(PK.into(), json!({"S": key.as_str()}));
    m.insert("cell".into(), json!({"S": route.cell}));
    m.insert("merchant_id".into(), json!({"S": route.merchant_id}));
    m.insert("kind".into(), json!({"S": route.kind.as_str()}));
    if let Some(e) = route.expires_at {
        m.insert("expires_at".into(), json!({"N": e.to_string()}));
    }
    Value::Object(m)
}

pub fn decode(item: &Value) -> Option<Item> {
    let s = |name: &str| item.get(name)?.get("S")?.as_str().map(str::to_owned);
    let expires_at = item
        .get("expires_at")
        .and_then(|v| v.get("N"))
        .and_then(Value::as_str)
        .and_then(|n| n.parse().ok());
    Some((
        LookupKey::from_raw(s(PK)?),
        Route {
            cell: s("cell")?,
            merchant_id: s("merchant_id")?,
            kind: Kind::parse(&s("kind")?)?,
            expires_at,
        },
    ))
}

fn key_json(key: &LookupKey) -> Value {
    json!({PK: {"S": key.as_str()}})
}

#[async_trait]
impl RouteStore for DynamoStore {
    async fn scan_all(&self) -> Result<Vec<Item>, StoreError> {
        self.paged("Scan", json!({"TableName": self.cfg.table}))
            .await
    }

    async fn get_many(&self, keys: &[LookupKey]) -> Result<Vec<Item>, StoreError> {
        let mut out = Vec::new();
        for chunk in keys.chunks(BATCH_GET) {
            let mut pending: Vec<Value> = chunk.iter().map(key_json).collect();
            for attempt in 1..=ATTEMPTS {
                let body = json!({"RequestItems": {self.cfg.table.as_str(): {"Keys": pending}}});
                let resp = self.call("BatchGetItem", body).await?;
                out.extend(
                    resp.get("Responses")
                        .and_then(|r| r.get(&self.cfg.table))
                        .and_then(Value::as_array)
                        .into_iter()
                        .flatten()
                        .filter_map(decode),
                );
                pending = resp
                    .get("UnprocessedKeys")
                    .and_then(|u| u.get(&self.cfg.table))
                    .and_then(|t| t.get("Keys"))
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                if pending.is_empty() {
                    break;
                }
                if attempt == ATTEMPTS {
                    return Err(StoreError::Service {
                        op: "BatchGetItem",
                        kind: "UnprocessedKeys".into(),
                        status: 200,
                    });
                }
            }
        }
        Ok(out)
    }

    async fn list_cell(&self, cell: &str) -> Result<Vec<Item>, StoreError> {
        self.paged(
            "Query",
            json!({
                "TableName": self.cfg.table,
                "IndexName": self.cfg.cell_index,
                "KeyConditionExpression": "cell = :c",
                "ExpressionAttributeValues": {":c": {"S": cell}},
            }),
        )
        .await
    }

    async fn put_many(&self, items: &[Item]) -> Result<(), StoreError> {
        self.write(
            items
                .iter()
                .map(|(k, r)| json!({"PutRequest": {"Item": encode(k, r)}}))
                .collect(),
        )
        .await
    }

    async fn delete_many(&self, keys: &[LookupKey]) -> Result<(), StoreError> {
        self.write(
            keys.iter()
                .map(|k| json!({"DeleteRequest": {"Key": key_json(k)}}))
                .collect(),
        )
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn item_round_trip() {
        let key = LookupKey::hashed("ab");
        let route = Route {
            cell: "cell-1".into(),
            merchant_id: "m1".into(),
            kind: Kind::ApiKey,
            expires_at: Some(1_900_000_000),
        };
        let (k, r) = decode(&encode(&key, &route)).expect("decodes");
        assert!(k == key);
        assert_eq!(r, route);
    }

    #[test]
    fn item_without_expiry() {
        let key = LookupKey::merchant("m1");
        let route = Route {
            cell: "cell-0".into(),
            merchant_id: "m1".into(),
            kind: Kind::Merchant,
            expires_at: None,
        };
        let raw = encode(&key, &route);
        assert!(raw.get("expires_at").is_none());
        assert_eq!(decode(&raw).expect("decodes").1, route);
    }

    #[test]
    fn unknown_kind_is_skipped() {
        let raw = json!({"lookup_key": {"S": "h#1"}, "cell": {"S": "c"}, "merchant_id": {"S": "m"}, "kind": {"S": "x"}});
        assert!(decode(&raw).is_none());
    }

    #[test]
    fn throttling_is_retried() {
        assert!(retryable("ProvisionedThroughputExceededException", 400));
        assert!(retryable("InternalServerError", 500));
        assert!(!retryable("ValidationException", 400));
    }
}
