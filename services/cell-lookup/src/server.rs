use std::sync::Arc;
use std::time::Instant;

use axum::extract::State;
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;

use crate::lookup::{credential, Decision, Resolver};
use crate::metrics::Metrics;

pub const CELL_HEADER: &str = "x-payments-cell";
pub const MERCHANT_HEADER: &str = "x-merchant-id";

#[derive(Clone)]
pub struct App {
    pub resolver: Arc<Resolver>,
    pub metrics: Arc<Metrics>,
    pub preflight_cell: String,
}

// Envoy ext_authz forwards the client's method and path, so every route is a check
pub fn authz_router(app: App) -> Router {
    Router::new().fallback(check).with_state(app)
}

// Health and metrics on their own listener, never reachable through the authz path
pub fn admin_router(app: App) -> Router {
    Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .route("/readyz", get(readyz))
        .route("/metrics", get(metrics))
        .with_state(app)
}

async fn check(State(app): State<App>, method: Method, uri: Uri, headers: HeaderMap) -> Response {
    let started = Instant::now();
    // Browsers send the preflight without the api-key header; every cell answers it the same way
    if method == Method::OPTIONS && credential::is_absent(&headers) {
        if let Ok(cell) = HeaderValue::from_str(&app.preflight_cell) {
            app.metrics
                .lookups
                .with_label_values(&["preflight", "skipped"])
                .inc();
            return (StatusCode::OK, [(CELL_HEADER, cell)]).into_response();
        }
    }
    let path = uri.path_and_query().map(|p| p.as_str()).unwrap_or("/");
    let (decision, source) = app.resolver.resolve(&headers, path).await;
    app.metrics
        .lookups
        .with_label_values(&[decision.label(), source.as_str()])
        .inc();
    let response = respond(decision, &headers);
    app.metrics
        .lookup_seconds
        .observe(started.elapsed().as_secs_f64());
    response
}

fn respond(decision: Decision, headers: &HeaderMap) -> Response {
    let (status, code, message) = match decision {
        Decision::Route(route) => {
            let mut out = HeaderMap::new();
            let Ok(cell) = HeaderValue::from_str(&route.cell) else {
                return error(
                    StatusCode::SERVICE_UNAVAILABLE,
                    "CL_03",
                    "Cell route is invalid",
                );
            };
            out.insert(CELL_HEADER, cell);
            if !headers.contains_key(MERCHANT_HEADER) {
                if let Ok(m) = HeaderValue::from_str(&route.merchant_id) {
                    out.insert(MERCHANT_HEADER, m);
                }
            }
            return (StatusCode::OK, out).into_response();
        }
        Decision::UnknownCredential => (StatusCode::FORBIDDEN, "CL_01", "API key not valid"),
        Decision::NoRoute => (
            StatusCode::NOT_FOUND,
            "CL_02",
            "No merchant for this request",
        ),
        Decision::Unavailable => (
            StatusCode::SERVICE_UNAVAILABLE,
            "CL_03",
            "Routing is unavailable, retry later",
        ),
    };
    error(status, code, message)
}

fn error(status: StatusCode, code: &str, message: &str) -> Response {
    let body = serde_json::json!({
        "error": {"type": "invalid_request", "code": code, "message": message}
    });
    let mut resp = (status, body.to_string()).into_response();
    resp.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json"),
    );
    if status == StatusCode::SERVICE_UNAVAILABLE {
        resp.headers_mut()
            .insert(header::RETRY_AFTER, HeaderValue::from_static("1"));
    }
    resp
}

async fn readyz(State(app): State<App>) -> StatusCode {
    if app.resolver.cache.ready() {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    }
}

async fn metrics(State(app): State<App>) -> impl IntoResponse {
    let age = app
        .resolver
        .cache
        .snapshot_age()
        .map(|a| a.as_secs_f64())
        .unwrap_or(-1.0);
    app.metrics.snapshot_age_seconds.set(age);
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        app.metrics.render(),
    )
}
