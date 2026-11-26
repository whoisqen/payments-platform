use axum::http::HeaderMap;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;

pub const API_KEY_HEADER: &str = "api-key";
pub const AUTHORIZATION_HEADER: &str = "authorization";

// The caller's credential, in the order the edge rate-key filter reads it
pub enum Credential {
    // Secret (env-prefixed) or publishable (pk_) key, both stored as keyed hashes
    Key(String),
    // Ephemeral keys live in the cell's Redis only, so they route by path or not at all
    Ephemeral,
    // Dashboard JWT; the signature is checked by the cell, the claim only chooses where to send it
    Jwt { merchant_id: String },
    None,
}

pub fn extract(headers: &HeaderMap) -> Credential {
    if let Some(key) = header(headers, API_KEY_HEADER) {
        if key.starts_with("epk_") {
            return Credential::Ephemeral;
        }
        return Credential::Key(key.to_owned());
    }
    match header(headers, AUTHORIZATION_HEADER) {
        Some(auth) => from_authorization(auth),
        None => Credential::None,
    }
}

pub fn is_absent(headers: &HeaderMap) -> bool {
    header(headers, API_KEY_HEADER).is_none() && header(headers, AUTHORIZATION_HEADER).is_none()
}

// Admin-key routes name the merchant in this header; it only picks that merchant's own cell
pub fn merchant_header(headers: &HeaderMap) -> Option<&str> {
    header(headers, "x-merchant-id").filter(|m| valid_merchant_id(m))
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty())
}

fn from_authorization(auth: &str) -> Credential {
    if let Some(token) = strip_prefix_ignore_case(auth, "bearer ") {
        return jwt_merchant(token.trim())
            .map(|merchant_id| Credential::Jwt { merchant_id })
            .unwrap_or(Credential::None);
    }
    if let Some(key) = comma_field(auth, &["api-key", "publishable-key"]) {
        return Credential::Key(key);
    }
    // SDK authorization: base64 of comma-separated fields, one of them publishable_key
    if let Some(key) = STANDARD
        .decode(auth)
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .and_then(|s| comma_field(&s, &["publishable_key"]))
    {
        return Credential::Key(key);
    }
    Credential::None
}

fn strip_prefix_ignore_case<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    let head = s.get(..prefix.len())?;
    head.eq_ignore_ascii_case(prefix)
        .then(|| &s[prefix.len()..])
}

fn comma_field(s: &str, names: &[&str]) -> Option<String> {
    s.split(',').find_map(|part| {
        let (name, value) = part.trim().split_once('=')?;
        let value = value.trim();
        (names.contains(&name.trim()) && !value.is_empty()).then(|| value.to_owned())
    })
}

fn jwt_merchant(token: &str) -> Option<String> {
    let mut parts = token.split('.');
    let (_, payload, _) = (parts.next()?, parts.next()?, parts.next()?);
    if parts.next().is_some() {
        return None;
    }
    let bytes = URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?;
    let claims: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    let merchant_id = claims.get("merchant_id")?.as_str()?;
    valid_merchant_id(merchant_id).then(|| merchant_id.to_owned())
}

// Hyperswitch merchant ids are short ASCII identifiers; anything else is not looked up
pub fn valid_merchant_id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    fn headers(pairs: &[(&'static str, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.insert(*k, HeaderValue::from_str(v).expect("header value"));
        }
        h
    }

    fn key_of(c: Credential) -> Option<String> {
        match c {
            Credential::Key(k) => Some(k),
            _ => None,
        }
    }

    #[test]
    fn api_key_header_wins_over_authorization() {
        let h = headers(&[
            ("api-key", " dev_abc "),
            ("authorization", "api-key=dev_other"),
        ]);
        assert_eq!(key_of(extract(&h)).as_deref(), Some("dev_abc"));
    }

    #[test]
    fn publishable_key_in_api_key_header() {
        let h = headers(&[("api-key", "pk_dev_123")]);
        assert_eq!(key_of(extract(&h)).as_deref(), Some("pk_dev_123"));
    }

    #[test]
    fn empty_api_key_falls_back_to_authorization() {
        let h = headers(&[
            ("api-key", ""),
            (
                "authorization",
                "publishable-key=pk_dev_1, client-secret=cs",
            ),
        ]);
        assert_eq!(key_of(extract(&h)).as_deref(), Some("pk_dev_1"));
    }

    #[test]
    fn authorization_api_key_field() {
        let h = headers(&[("authorization", "api-key=dev_9")]);
        assert_eq!(key_of(extract(&h)).as_deref(), Some("dev_9"));
    }

    #[test]
    fn sdk_authorization_carries_publishable_key() {
        let raw = STANDARD.encode("profile_id=pro_1,publishable_key=pk_dev_7,client_secret=x");
        let h = headers(&[("authorization", &raw)]);
        assert_eq!(key_of(extract(&h)).as_deref(), Some("pk_dev_7"));
    }

    #[test]
    fn ephemeral_key_is_not_looked_up() {
        let h = headers(&[("api-key", "epk_123")]);
        assert!(matches!(extract(&h), Credential::Ephemeral));
    }

    #[test]
    fn jwt_merchant_claim() {
        let payload =
            URL_SAFE_NO_PAD.encode(r#"{"user_id":"u","merchant_id":"merchant_1","exp":1}"#);
        let h = headers(&[(
            "authorization",
            &format!("Bearer eyJhbGciOiJIUzI1NiJ9.{payload}.sig"),
        )]);
        match extract(&h) {
            Credential::Jwt { merchant_id } => assert_eq!(merchant_id, "merchant_1"),
            _ => panic!("expected jwt"),
        }
    }

    #[test]
    fn jwt_with_bad_merchant_is_ignored() {
        let payload = URL_SAFE_NO_PAD.encode(r#"{"merchant_id":"a/b"}"#);
        let h = headers(&[("authorization", &format!("bearer x.{payload}.y"))]);
        assert!(matches!(extract(&h), Credential::None));
    }

    #[test]
    fn no_credential() {
        assert!(matches!(extract(&HeaderMap::new()), Credential::None));
        let h = headers(&[("authorization", "Basic Zm9vOmJhcg==")]);
        assert!(matches!(extract(&h), Credential::None));
    }
}
