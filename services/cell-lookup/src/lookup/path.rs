use super::credential::valid_merchant_id;

// Routes that carry the merchant in the path and often no credential: PSP webhooks, redirects, links
pub const DEFAULT_RULES: &[&str] = &[
    "/webhooks/{merchant_id}/*",
    "/webhooks/relay/{merchant_id}/*",
    "/v2/webhooks/{merchant_id}/*/*",
    "/v2/webhooks/recovery/{merchant_id}/*/*",
    "/payments/redirect/*/{merchant_id}/*",
    "/payments/*/{merchant_id}/redirect/**",
    "/payments/*/{merchant_id}/authorize/*",
    "/payment_link/{merchant_id}/*",
    "/payment_link/s/{merchant_id}/*",
    "/payment_link/status/{merchant_id}/*",
    "/payout_link/{merchant_id}/*",
    "/payment_methods/collect/{merchant_id}/*",
    "/authentication/{merchant_id}/*/redirect",
    "/authentication/{merchant_id}/*/sync",
    "/account/{merchant_id}/**",
    "/api_keys/{merchant_id}/**",
];

#[derive(Clone, Debug, PartialEq, Eq)]
enum Segment {
    Literal(String),
    Any,
    Merchant,
    Rest,
}

#[derive(Clone, Debug)]
pub struct PathRule(Vec<Segment>);

#[derive(Debug, thiserror::Error)]
#[error("path rule {0:?} is invalid: {1}")]
pub struct PathRuleError(String, &'static str);

impl PathRule {
    pub fn parse(rule: &str) -> Result<Self, PathRuleError> {
        let err = |why| PathRuleError(rule.to_owned(), why);
        let segments: Vec<Segment> = split(rule)
            .map(|s| match s {
                "*" => Segment::Any,
                "**" => Segment::Rest,
                "{merchant_id}" => Segment::Merchant,
                lit => Segment::Literal(lit.to_owned()),
            })
            .collect();
        if segments.iter().filter(|s| **s == Segment::Merchant).count() != 1 {
            return Err(err("needs exactly one {merchant_id} segment"));
        }
        if let Some(i) = segments.iter().position(|s| *s == Segment::Rest) {
            if i + 1 != segments.len() {
                return Err(err("** must be the last segment"));
            }
        }
        Ok(Self(segments))
    }

    fn merchant<'a>(&self, path: &[&'a str]) -> Option<&'a str> {
        let mut found = None;
        for (i, seg) in self.0.iter().enumerate() {
            if *seg == Segment::Rest {
                return found;
            }
            let part = *path.get(i)?;
            match seg {
                Segment::Literal(l) if l != part => return None,
                Segment::Merchant => found = Some(part),
                _ => {}
            }
        }
        (path.len() == self.0.len()).then_some(found).flatten()
    }
}

fn split(path: &str) -> impl Iterator<Item = &str> {
    path.split('/').filter(|s| !s.is_empty())
}

pub struct PathRules(Vec<PathRule>);

impl PathRules {
    pub fn parse<S: AsRef<str>>(rules: &[S]) -> Result<Self, PathRuleError> {
        rules
            .iter()
            .map(|r| PathRule::parse(r.as_ref()))
            .collect::<Result<_, _>>()
            .map(Self)
    }

    pub fn defaults() -> Self {
        Self::parse(DEFAULT_RULES).unwrap_or_else(|_| Self(Vec::new()))
    }

    pub fn merchant_of<'a>(&self, path_and_query: &'a str) -> Option<&'a str> {
        let path = path_and_query.split(['?', '#']).next().unwrap_or("");
        let parts: Vec<&str> = split(path).collect();
        self.0
            .iter()
            .find_map(|r| r.merchant(&parts))
            .filter(|m| valid_merchant_id(m))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_rules_parse() {
        assert_eq!(
            PathRules::parse(DEFAULT_RULES).expect("rules").0.len(),
            DEFAULT_RULES.len()
        );
    }

    #[test]
    fn webhook_paths() {
        let r = PathRules::defaults();
        assert_eq!(
            r.merchant_of("/webhooks/merchant_1/stripe"),
            Some("merchant_1")
        );
        assert_eq!(
            r.merchant_of("/webhooks/relay/merchant_2/mca_1?x=1"),
            Some("merchant_2")
        );
        assert_eq!(
            r.merchant_of("/v2/webhooks/merchant_3/pro_1/mca_1"),
            Some("merchant_3")
        );
    }

    #[test]
    fn redirect_paths() {
        let r = PathRules::defaults();
        assert_eq!(
            r.merchant_of("/payments/redirect/pay_1/m1/att_1"),
            Some("m1")
        );
        assert_eq!(
            r.merchant_of("/payments/pay_1/m2/redirect/response/adyen"),
            Some("m2")
        );
        assert_eq!(
            r.merchant_of("/payments/pay_1/m3/redirect/complete/adyen/creds"),
            Some("m3")
        );
        assert_eq!(
            r.merchant_of("/payments/pay_1/m4/authorize/adyen"),
            Some("m4")
        );
        assert_eq!(r.merchant_of("/account/m5"), Some("m5"));
    }

    #[test]
    fn unrelated_paths() {
        let r = PathRules::defaults();
        assert_eq!(r.merchant_of("/payments"), None);
        assert_eq!(r.merchant_of("/payments/pay_1/confirm"), None);
        assert_eq!(r.merchant_of("/webhooks/m1"), None);
        assert_eq!(r.merchant_of("/webhooks/m%2F1/stripe"), None);
    }

    #[test]
    fn invalid_rules() {
        assert!(PathRule::parse("/a/*").is_err());
        assert!(PathRule::parse("/a/**/{merchant_id}").is_err());
    }
}
