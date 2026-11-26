pub mod dynamodb;
pub mod memory;

use async_trait::async_trait;

use crate::lookup::hash::LookupKey;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    ApiKey,
    PublishableKey,
    Merchant,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::ApiKey => "api_key",
            Kind::PublishableKey => "publishable_key",
            Kind::Merchant => "merchant",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "api_key" => Some(Kind::ApiKey),
            "publishable_key" => Some(Kind::PublishableKey),
            "merchant" => Some(Kind::Merchant),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Route {
    pub cell: String,
    pub merchant_id: String,
    pub kind: Kind,
    // Unix seconds; also the table's TTL attribute
    pub expires_at: Option<i64>,
}

impl Route {
    pub fn expired(&self, now: i64) -> bool {
        self.expires_at.is_some_and(|e| e <= now)
    }
}

pub type Item = (LookupKey, Route);

// Messages carry the operation and the AWS error type only, never a key or a hash
#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("{op}: transport error: {reason}")]
    Transport { op: &'static str, reason: String },
    #[error("{op}: service error {kind} (http {status})")]
    Service {
        op: &'static str,
        kind: String,
        status: u16,
    },
    #[error("{op}: unexpected response: {reason}")]
    Decode { op: &'static str, reason: String },
    #[error("{op}: credentials: {reason}")]
    Credentials { op: &'static str, reason: String },
}

// The route table; DynamoDB in production, memory in tests
#[async_trait]
pub trait RouteStore: Send + Sync {
    async fn scan_all(&self) -> Result<Vec<Item>, StoreError>;
    async fn get_many(&self, keys: &[LookupKey]) -> Result<Vec<Item>, StoreError>;
    async fn list_cell(&self, cell: &str) -> Result<Vec<Item>, StoreError>;
    async fn put_many(&self, items: &[Item]) -> Result<(), StoreError>;
    async fn delete_many(&self, keys: &[LookupKey]) -> Result<(), StoreError>;
}
