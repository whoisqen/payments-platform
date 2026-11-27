use tracing_subscriber::EnvFilter;

// Signing and driver crates trace request contents at debug level; they stay at warn whatever RUST_LOG says
const PINNED: &[&str] = &[
    "aws_sigv4=warn",
    "aws_smithy_runtime=warn",
    "sqlx=warn",
    "hyper=warn",
    "reqwest=warn",
];

pub fn init() {
    let base = std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into());
    let mut filter = EnvFilter::new(base);
    for d in PINNED {
        if let Ok(directive) = d.parse() {
            filter = filter.add_directive(directive);
        }
    }
    tracing_subscriber::fmt()
        .json()
        .flatten_event(true)
        .with_current_span(false)
        .with_env_filter(filter)
        .init();
}
