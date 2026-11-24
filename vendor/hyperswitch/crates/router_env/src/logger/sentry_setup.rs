//! Error tracking with Sentry.
//!
//! Nothing that can hold card data or a secret leaves the process: request data, user data and the
//! server name are dropped, and every text of an event and of a breadcrumb goes through [`scrub`].

use std::{borrow::Cow, fmt, sync::Arc};

use regex::Regex;
use sentry::{
    protocol::{Breadcrumb, Event, Value},
    ClientInitGuard, ClientOptions,
};

use crate::config;

const REDACTED_PAN: &str = "[REDACTED-PAN]";
const REDACTED_SECRET: &str = "[REDACTED-SECRET]";
/// Longest text of an event or a breadcrumb that is sent.
const MAX_TEXT: usize = 2048;

struct Patterns {
    pan: Regex,
    secrets: Vec<Regex>,
}

fn patterns() -> &'static Patterns {
    static PATTERNS: std::sync::OnceLock<Patterns> = std::sync::OnceLock::new();
    PATTERNS.get_or_init(|| Patterns {
        // 13 to 19 digits, with spaces or dashes between them
        pan: Regex::new(r"\b(?:\d[ -]?){12,18}\d\b").expect("PAN pattern is valid"),
        secrets: [
            r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{8,}",
            r"(?i)\bbasic\s+[A-Za-z0-9+/=]{8,}",
            r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b",
            r"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*",
            r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
            r#"(?i)(password|passwd|secret|api[_-]?key|token|cvv|cvc)["']?\s*[:=]\s*["']?[^\s"',;&]+"#,
        ]
        .iter()
        .map(|p| Regex::new(p).expect("secret pattern is valid"))
        .collect(),
    })
}

/// Replace card numbers and secrets in a text and cut it to a bounded length.
pub fn scrub(text: &str) -> String {
    let patterns = patterns();
    let mut out = patterns.pan.replace_all(text, REDACTED_PAN).into_owned();
    for secret in &patterns.secrets {
        out = secret.replace_all(&out, REDACTED_SECRET).into_owned();
    }
    if out.len() > MAX_TEXT {
        let mut end = MAX_TEXT;
        while !out.is_char_boundary(end) {
            end -= 1;
        }
        out.truncate(end);
    }
    out
}

fn scrub_value(value: &mut Value) {
    match value {
        Value::String(text) => *text = scrub(text),
        Value::Array(items) => items.iter_mut().for_each(scrub_value),
        Value::Object(map) => map.values_mut().for_each(scrub_value),
        _ => {}
    }
}

/// Remove everything from an event that can carry card data or a secret.
pub fn scrub_event(mut event: Event<'static>) -> Event<'static> {
    // Request bodies, headers, cookies and query strings, user data and host names are never sent.
    event.request = None;
    event.user = None;
    event.server_name = None;
    event.message = event.message.map(|m| scrub(&m));
    if let Some(logentry) = event.logentry.as_mut() {
        logentry.message = scrub(&logentry.message);
        logentry.params.iter_mut().for_each(scrub_value);
    }
    for exception in event.exception.values.iter_mut() {
        exception.value = exception.value.take().map(|v| scrub(&v));
        // Local variables of stack frames are not part of the events either
        if let Some(stacktrace) = exception.stacktrace.as_mut() {
            for frame in stacktrace.frames.iter_mut() {
                frame.vars.clear();
            }
        }
    }
    event.extra.values_mut().for_each(scrub_value);
    event.tags.values_mut().for_each(|tag| *tag = scrub(tag));
    event.breadcrumbs.values = event.breadcrumbs.values.into_iter().filter_map(scrub_breadcrumb).collect();
    event
}

/// Scrub the text of a breadcrumb and its data.
pub fn scrub_breadcrumb(mut crumb: Breadcrumb) -> Option<Breadcrumb> {
    crumb.message = crumb.message.map(|m| scrub(&m));
    crumb.data.values_mut().for_each(scrub_value);
    Some(crumb)
}

/// Keeps the Sentry client alive and sends the pending events when it is dropped.
pub struct SentryGuard(#[allow(dead_code)] ClientInitGuard);

impl fmt::Debug for SentryGuard {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("SentryGuard")
    }
}

/// Start the Sentry client when a DSN is configured; the guard flushes the events on drop.
pub fn setup(config: &config::LogSentry, service_name: &str) -> Option<SentryGuard> {
    let dsn = config.dsn.as_deref().filter(|dsn| !dsn.is_empty())?;
    // The builder panics outside 0.0..=1.0, and a bad value in a file must not stop the service
    let rate = config.sample_rate.unwrap_or(1.0).clamp(0.0, 1.0);
    // No performance traces: they are sent to OpenTelemetry
    let mut options = ClientOptions::default().sample_rate(rate).traces_sample_rate(0.0);
    // The environment is the RUN_ENV of the deployment when the config names none
    options.environment = config
        .environment
        .clone()
        .or_else(|| std::env::var("RUN_ENV").ok())
        .map(Cow::Owned);
    options.release = config.release.clone().map(Cow::Owned);
    options.send_default_pii = false;
    options.attach_stacktrace = true;
    options.server_name = Some(Cow::Owned(service_name.to_owned()));
    options.before_send = Some(Arc::new(|event| Some(scrub_event(event))));
    options.before_breadcrumb = Some(Arc::new(scrub_breadcrumb));
    Some(SentryGuard(sentry::init((dsn, options))))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn card_numbers_are_redacted_with_or_without_separators() {
        for pan in ["4111111111111111", "4111 1111 1111 1111", "4111-1111-1111-1111", "378282246310005"] {
            assert_eq!(scrub(&format!("payment failed for {pan} today")), "payment failed for [REDACTED-PAN] today");
        }
    }

    #[test]
    fn short_numbers_and_ids_are_left_alone() {
        let text = "status 500 after 1234 ms for attempt pay_abc123";
        assert_eq!(scrub(text), text);
    }

    #[test]
    fn secrets_are_redacted() {
        // The samples are put together here so that no complete key is written in the source
        let aws_key = format!("{}{}", "AKIA", "ABCDEFGHIJKLMNOP");
        let api_key = format!("{}{}", "sk_live_", "1234567890abcdef");
        for text in [
            "Authorization: Bearer abcdefghijklmnop".to_owned(),
            format!("key {aws_key} leaked"),
            "password=hunter2".to_owned(),
            format!("api_key: {api_key}"),
            "token\":\"abc.def\"".to_owned(),
        ] {
            assert!(scrub(&text).contains(REDACTED_SECRET), "{text}");
        }
    }

    #[test]
    fn long_text_is_cut_on_a_character_boundary() {
        let text = "é".repeat(MAX_TEXT);
        let out = scrub(&text);
        assert!(out.len() <= MAX_TEXT);
        assert!(out.chars().all(|c| c == 'é'));
    }

    #[test]
    fn an_event_loses_request_user_host_and_card_data() {
        let mut event = Event::default();
        event.request = Some(Default::default());
        event.user = Some(Default::default());
        event.server_name = Some(Cow::Borrowed("node-1"));
        event.message = Some("charge 4111111111111111 declined".into());
        event.extra.insert("body".into(), Value::String("card 4111 1111 1111 1111".into()));
        event.tags.insert("note".into(), "cvv=123".into());
        let event = scrub_event(event);
        assert!(event.request.is_none() && event.user.is_none() && event.server_name.is_none());
        assert_eq!(event.message.as_deref(), Some("charge [REDACTED-PAN] declined"));
        assert_eq!(event.extra["body"], Value::String("card [REDACTED-PAN]".into()));
        assert_eq!(event.tags["note"], REDACTED_SECRET);
    }

    #[test]
    fn nothing_starts_without_a_dsn() {
        assert!(setup(&config::LogSentry::default(), "router").is_none());
        let empty = config::LogSentry { dsn: Some(String::new()), ..Default::default() };
        assert!(setup(&empty, "router").is_none());
    }
}
