use thiserror::Error;

const HASH_KEY_LEN: usize = 32;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum HashKeyError {
    #[error("hash key for cell {0} is not valid hex")]
    NotHex(String),
    #[error("hash key for cell {0} is not {HASH_KEY_LEN} bytes")]
    WrongLength(String),
}

// Same derivation as Hyperswitch ApiKeys::get_hash_key and PlaintextApiKey::keyed_hash
pub struct HashKey([u8; HASH_KEY_LEN]);

impl HashKey {
    pub fn from_hex(cell: &str, hex_key: &str) -> Result<Self, HashKeyError> {
        let bytes = hex::decode(hex_key.trim()).map_err(|_| HashKeyError::NotHex(cell.into()))?;
        let key = <[u8; HASH_KEY_LEN]>::try_from(bytes.as_slice())
            .map_err(|_| HashKeyError::WrongLength(cell.into()))?;
        Ok(Self(key))
    }

    pub fn keyed_hash(&self, plaintext: &str) -> String {
        blake3::keyed_hash(&self.0, plaintext.as_bytes())
            .to_hex()
            .to_string()
    }
}

pub struct CellKey {
    pub cell: String,
    pub key: HashKey,
}

// Each cell has its own hash key, so a credential is hashed once per cell
pub struct CellKeys(Vec<CellKey>);

impl CellKeys {
    pub fn new(keys: Vec<CellKey>) -> Self {
        Self(keys)
    }

    pub fn cells(&self) -> impl Iterator<Item = &str> {
        self.0.iter().map(|k| k.cell.as_str())
    }

    pub fn get(&self, cell: &str) -> Option<&HashKey> {
        self.0.iter().find(|k| k.cell == cell).map(|k| &k.key)
    }

    pub fn candidates(&self, plaintext: &str) -> Vec<Candidate> {
        self.0
            .iter()
            .map(|k| Candidate {
                cell: k.cell.clone(),
                key: LookupKey::hashed(&k.key.keyed_hash(plaintext)),
            })
            .collect()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

// Item key in the route table: h#<keyed hash> for credentials, m#<merchant_id> for merchants
#[derive(Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct LookupKey(String);

impl LookupKey {
    pub fn hashed(hex_hash: &str) -> Self {
        Self(format!("h#{hex_hash}"))
    }

    pub fn merchant(merchant_id: &str) -> Self {
        Self(format!("m#{merchant_id}"))
    }

    pub fn from_raw(raw: String) -> Self {
        Self(raw)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn is_merchant(&self) -> bool {
        self.0.starts_with("m#")
    }
}

pub struct Candidate {
    pub cell: String,
    pub key: LookupKey,
}

#[cfg(test)]
mod tests {
    use super::*;

    // Dev hash key of vendor config; vectors computed apart from this crate with vendor api_keys.rs code
    const DEV_HASH_KEY: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    #[test]
    fn hash_matches_hyperswitch_for_a_secret_key() {
        let key = HashKey::from_hex("cell-0", DEV_HASH_KEY).expect("valid key");
        assert_eq!(
            key.keyed_hash("dev_Kq2z8pR4tW6yU1iO3aS5dF7gH9jK0lZx"),
            "0a6fd41859b1e1736a054936bbabe9f7f3e47a05c955fab68330eff46b39ee59"
        );
    }

    #[test]
    fn hash_matches_for_a_publishable_key() {
        let key = HashKey::from_hex("cell-0", DEV_HASH_KEY).expect("valid key");
        assert_eq!(
            key.keyed_hash("pk_dev_5f1e2d3c4b5a69788796a5b4c3d2e1f0"),
            "c518866f6c6851f0d7a57983e54ca303c7ac6b2055227d1a54c6a8885b0a3dba"
        );
    }

    #[test]
    fn rejects_bad_keys_without_echoing_them() {
        assert_eq!(
            HashKey::from_hex("cell-0", "zz").err(),
            Some(HashKeyError::NotHex("cell-0".into()))
        );
        assert_eq!(
            HashKey::from_hex("cell-0", "00ff").err(),
            Some(HashKeyError::WrongLength("cell-0".into()))
        );
    }

    #[test]
    fn one_candidate_per_cell() {
        let keys = CellKeys::new(vec![
            CellKey {
                cell: "cell-0".into(),
                key: HashKey::from_hex("cell-0", DEV_HASH_KEY).expect("valid key"),
            },
            CellKey {
                cell: "cell-1".into(),
                key: HashKey::from_hex("cell-1", &"11".repeat(32)).expect("valid key"),
            },
        ]);
        let c = keys.candidates("dev_x");
        assert_eq!(c.len(), 2);
        assert_ne!(c[0].key.as_str(), c[1].key.as_str());
        assert!(c[0].key.as_str().starts_with("h#"));
    }
}
