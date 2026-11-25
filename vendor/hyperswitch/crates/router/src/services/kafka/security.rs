//! Transport security and SASL authentication for the Kafka producer, including
//! the Amazon MSK IAM `OAUTHBEARER` token provider.

use std::{
    error::Error,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use aws_credential_types::{provider::ProvideCredentials, Credentials};
use aws_sigv4::{
    http_request::{sign, SignableBody, SignableRequest, SignatureLocation, SigningSettings},
    sign::v4,
};
use base64::Engine;
use rdkafka::{
    client::{ClientContext, OAuthToken},
    producer::{DeliveryResult, ProducerContext},
};

type BoxError = Box<dyn Error + Send + Sync>;

const MSK_IAM_SERVICE: &str = "kafka-cluster";
const MSK_IAM_TOKEN_TTL: Duration = Duration::from_secs(900);
const MSK_IAM_USER_AGENT: &str = "hyperswitch-msk-iam";
const MSK_IAM_PRINCIPAL: &str = "aws-msk-iam";
const AWS_CREDENTIALS_TIMEOUT: Duration = Duration::from_secs(10);

/// librdkafka `security.protocol`; left unset (PLAINTEXT) when absent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum KafkaSecurityProtocol {
    Plaintext,
    Ssl,
    SaslSsl,
}

impl KafkaSecurityProtocol {
    fn as_str(self) -> &'static str {
        match self {
            Self::Plaintext => "PLAINTEXT",
            Self::Ssl => "SSL",
            Self::SaslSsl => "SASL_SSL",
        }
    }
}

/// librdkafka `sasl.mechanism`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum KafkaSaslMechanism {
    Oauthbearer,
}

impl KafkaSaslMechanism {
    fn as_str(self) -> &'static str {
        match self {
            Self::Oauthbearer => "OAUTHBEARER",
        }
    }
}

/// Source of `OAUTHBEARER` tokens.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KafkaOauthbearerProvider {
    AwsMskIam,
}

/// Security-related view of `KafkaSettings`.
#[derive(Debug, Clone, Copy)]
pub(super) struct KafkaSecurity<'a> {
    pub security_protocol: Option<KafkaSecurityProtocol>,
    pub sasl_mechanism: Option<KafkaSaslMechanism>,
    pub sasl_oauthbearer_provider: Option<KafkaOauthbearerProvider>,
    pub aws_region: Option<&'a str>,
}

impl KafkaSecurity<'_> {
    pub(super) fn validate(&self) -> Result<(), String> {
        match (self.sasl_mechanism, self.sasl_oauthbearer_provider) {
            (Some(KafkaSaslMechanism::Oauthbearer), None) => {
                return Err(
                    "Kafka sasl_mechanism OAUTHBEARER requires sasl_oauthbearer_provider".into(),
                )
            }
            (None, Some(_)) => {
                return Err(
                    "Kafka sasl_oauthbearer_provider requires sasl_mechanism OAUTHBEARER".into(),
                )
            }
            _ => {}
        }
        match (self.security_protocol, self.sasl_mechanism) {
            (Some(KafkaSecurityProtocol::SaslSsl), None) => {
                Err("Kafka security_protocol SASL_SSL requires sasl_mechanism".into())
            }
            (Some(KafkaSecurityProtocol::SaslSsl), Some(_)) => Ok(()),
            (_, Some(_)) => Err("Kafka sasl_mechanism requires security_protocol SASL_SSL".into()),
            (_, None) => Ok(()),
        }
    }

    pub(super) fn apply(&self, config: &mut rdkafka::ClientConfig) {
        if let Some(protocol) = self.security_protocol {
            config.set("security.protocol", protocol.as_str());
        }
        if let Some(mechanism) = self.sasl_mechanism {
            config.set("sasl.mechanism", mechanism.as_str());
        }
    }

    pub(super) fn context(&self) -> KafkaClientContext {
        KafkaClientContext {
            msk_iam: matches!(
                self.sasl_oauthbearer_provider,
                Some(KafkaOauthbearerProvider::AwsMskIam)
            )
            .then(|| MskIamTokenProvider {
                region: self.aws_region.map(str::to_owned),
            }),
        }
    }
}

/// Producer context that supplies `OAUTHBEARER` tokens when configured; otherwise
/// behaves like `DefaultProducerContext`.
pub(super) struct KafkaClientContext {
    msk_iam: Option<MskIamTokenProvider>,
}

impl ClientContext for KafkaClientContext {
    // librdkafka only emits refresh events when sasl.mechanism is OAUTHBEARER.
    const ENABLE_REFRESH_OAUTH_TOKEN: bool = true;

    fn generate_oauth_token(
        &self,
        _oauthbearer_config: Option<&str>,
    ) -> Result<OAuthToken, Box<dyn Error>> {
        match &self.msk_iam {
            Some(provider) => provider.generate().map_err(|error| {
                let error: Box<dyn Error> = error;
                error
            }),
            None => Err("no Kafka OAUTHBEARER token provider is configured".into()),
        }
    }
}

impl ProducerContext for KafkaClientContext {
    type DeliveryOpaque = ();

    fn delivery(&self, _: &DeliveryResult<'_>, _: Self::DeliveryOpaque) {}
}

#[derive(Debug, Clone)]
struct MskIamTokenProvider {
    region: Option<String>,
}

impl MskIamTokenProvider {
    fn generate(&self) -> Result<OAuthToken, BoxError> {
        let region = self.region.clone();
        // librdkafka may call this on a Tokio worker (e.g. flush on drop), where a nested runtime would panic.
        std::thread::spawn(move || fetch_and_sign(region))
            .join()
            .map_err(|_| BoxError::from("MSK IAM token thread panicked"))?
    }
}

fn fetch_and_sign(region: Option<String>) -> Result<OAuthToken, BoxError> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let (credentials, region) = runtime.block_on(async {
        let mut loader = aws_config::defaults(aws_config::BehaviorVersion::latest());
        if let Some(region) = region {
            loader = loader.region(aws_config::Region::new(region));
        }
        let sdk_config = loader.load().await;
        let region = sdk_config
            .region()
            .ok_or("no AWS region for MSK IAM; set aws_region")?
            .to_string();
        let provider = sdk_config
            .credentials_provider()
            .ok_or("no AWS credentials provider for MSK IAM")?;
        let credentials =
            tokio::time::timeout(AWS_CREDENTIALS_TIMEOUT, provider.provide_credentials()).await??;
        Ok::<_, BoxError>((credentials, region))
    })?;
    let now = SystemTime::from(common_utils::date_time::now().assume_utc());
    Ok(OAuthToken {
        token: msk_iam_token(&credentials, &region, now)?,
        principal_name: MSK_IAM_PRINCIPAL.to_owned(),
        lifetime_ms: token_expiry_ms(now)?,
    })
}

fn token_expiry_ms(signed_at: SystemTime) -> Result<i64, BoxError> {
    Ok(i64::try_from(
        (signed_at + MSK_IAM_TOKEN_TTL)
            .duration_since(UNIX_EPOCH)?
            .as_millis(),
    )?)
}

/// MSK IAM token: base64url (no padding) of a SigV4 presigned `kafka-cluster:Connect` URL.
fn msk_iam_token(
    credentials: &Credentials,
    region: &str,
    signed_at: SystemTime,
) -> Result<String, BoxError> {
    let url = format!("https://kafka.{region}.amazonaws.com/?Action=kafka-cluster%3AConnect");
    let identity = credentials.clone().into();
    let mut settings = SigningSettings::default();
    settings.signature_location = SignatureLocation::QueryParams;
    settings.expires_in = Some(MSK_IAM_TOKEN_TTL);
    let params = v4::SigningParams::builder()
        .identity(&identity)
        .region(region)
        .name(MSK_IAM_SERVICE)
        .time(signed_at)
        .settings(settings)
        .build()?
        .into();
    let request = SignableRequest::new(
        "GET",
        url.as_str(),
        std::iter::empty(),
        SignableBody::Bytes(&[]),
    )?;
    let (instructions, _signature) = sign(request, &params)?.into_parts();
    let mut signed = url::Url::parse(&url)?;
    {
        let mut query = signed.query_pairs_mut();
        for (name, value) in instructions.params() {
            query.append_pair(name, value);
        }
        query.append_pair("User-Agent", MSK_IAM_USER_AGENT);
    }
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(signed.as_str()))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]

    use std::collections::HashMap;

    use super::*;

    fn security(
        security_protocol: Option<KafkaSecurityProtocol>,
        sasl_mechanism: Option<KafkaSaslMechanism>,
        sasl_oauthbearer_provider: Option<KafkaOauthbearerProvider>,
    ) -> KafkaSecurity<'static> {
        KafkaSecurity {
            security_protocol,
            sasl_mechanism,
            sasl_oauthbearer_provider,
            aws_region: None,
        }
    }

    #[test]
    fn validate_accepts_supported_combinations() {
        assert!(security(None, None, None).validate().is_ok());
        assert!(security(Some(KafkaSecurityProtocol::Ssl), None, None)
            .validate()
            .is_ok());
        assert!(security(
            Some(KafkaSecurityProtocol::SaslSsl),
            Some(KafkaSaslMechanism::Oauthbearer),
            Some(KafkaOauthbearerProvider::AwsMskIam),
        )
        .validate()
        .is_ok());
    }

    #[test]
    fn validate_rejects_incomplete_sasl() {
        assert!(security(Some(KafkaSecurityProtocol::SaslSsl), None, None)
            .validate()
            .is_err());
        assert!(security(
            Some(KafkaSecurityProtocol::SaslSsl),
            Some(KafkaSaslMechanism::Oauthbearer),
            None,
        )
        .validate()
        .is_err());
        assert!(security(
            Some(KafkaSecurityProtocol::Ssl),
            Some(KafkaSaslMechanism::Oauthbearer),
            Some(KafkaOauthbearerProvider::AwsMskIam),
        )
        .validate()
        .is_err());
        assert!(
            security(None, None, Some(KafkaOauthbearerProvider::AwsMskIam))
                .validate()
                .is_err()
        );
    }

    #[test]
    fn msk_iam_token_is_a_presigned_connect_url() {
        let credentials =
            Credentials::new("AKIDEXAMPLE", "secret", Some("tok+/=".into()), None, "test");
        let signed_at = UNIX_EPOCH + Duration::from_secs(1_700_000_000);
        let token = msk_iam_token(&credentials, "eu-central-1", signed_at).unwrap();
        assert!(!token.contains('=') && !token.contains('+') && !token.contains('/'));
        let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(&token)
            .unwrap();
        let url = url::Url::parse(std::str::from_utf8(&decoded).unwrap()).unwrap();
        assert_eq!(url.host_str(), Some("kafka.eu-central-1.amazonaws.com"));
        let query: HashMap<String, String> = url.query_pairs().into_owned().collect();
        assert_eq!(query["Action"], "kafka-cluster:Connect");
        assert_eq!(query["X-Amz-Algorithm"], "AWS4-HMAC-SHA256");
        assert_eq!(
            query["X-Amz-Credential"],
            "AKIDEXAMPLE/20231114/eu-central-1/kafka-cluster/aws4_request"
        );
        assert_eq!(query["X-Amz-Date"], "20231114T221320Z");
        assert_eq!(query["X-Amz-Expires"], "900");
        assert_eq!(query["X-Amz-SignedHeaders"], "host");
        assert_eq!(query["X-Amz-Security-Token"], "tok+/=");
        assert_eq!(query["X-Amz-Signature"].len(), 64);
        assert_eq!(query["User-Agent"], MSK_IAM_USER_AGENT);
        assert_eq!(token_expiry_ms(signed_at).unwrap(), 1_700_000_900_000);
    }
}
