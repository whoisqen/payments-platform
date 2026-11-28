import json
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

from smoke import live

LOOPBACK = ("localhost", "127.0.0.1", "::1")
CALL_TIMEOUT = 20.0


class Failed(Exception):
    pass


def check_url(url, compose_hosts=()):
    p = urllib.parse.urlsplit(url)
    host = (p.hostname or "").lower()
    if p.scheme not in ("http", "https") or p.username or p.password:
        raise ValueError("API URL must be http(s) without credentials")
    # plain http only to the local compose stack; a shared environment is reached over TLS
    if p.scheme == "http" and host not in LOOPBACK and host not in compose_hosts:
        raise ValueError("plain http is allowed only for a local stack")
    return host


class Client:
    def __init__(self, base, api_key=None, admin_key=None, cell=None):
        self.base = base.rstrip("/")
        self.api_key, self.admin_key = api_key, admin_key
        # the edge routes by cell and answers 503 without one; shared environments resolve it from the merchant
        self.cell = cell
        self.opener = live._opener()

    def call(self, method, path, body=None, key="api", headers=None):
        h = {"Content-Type": "application/json", "Accept": "application/json", **(headers or {})}
        if self.cell:
            h.setdefault("x-payments-cell", self.cell)
        secret = {"api": self.api_key, "admin": self.admin_key}.get(key)
        if secret:
            h["api-key"] = secret
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=h)
        try:
            with self.opener.open(req, timeout=CALL_TIMEOUT) as r:
                status, raw = r.status, r.read(1 << 20)
        except urllib.error.HTTPError as err:
            status, raw = err.code, err.read(1 << 20)
        except Exception as err:  # the message may hold the URL, keep the class only
            raise Failed(f"{method} {path.split('/')[1] if '/' in path else path}: {type(err).__name__}") from None
        try:
            out = json.loads(raw) if raw else {}
        except ValueError:
            out = None
        return status, out


def payment_contract(obj):
    missing = [k for k in ("payment_id", "status", "amount", "currency") if not isinstance(obj, dict) or k not in obj]
    if missing:
        raise Failed("payment response lacks " + ", ".join(missing))
    if not isinstance(obj["amount"], int) or not isinstance(obj["payment_id"], str):
        raise Failed("payment response has wrong field types")


def error_contract(obj):
    err = obj.get("error") if isinstance(obj, dict) else None
    if not isinstance(err, dict) or not all(isinstance(err.get(k), str) for k in ("type", "message", "code")):
        raise Failed("error response is not {error: {type, message, code}}")


def expect(status, out, wanted, step):
    if status not in wanted:
        raise Failed(f"{step}: HTTP {status}")
    return out


def bootstrap(client, connector):
    mid = "ci_" + secrets.token_hex(6)
    s, acc = client.call("POST", "/accounts", {"merchant_id": mid, "merchant_name": "ci integration"}, key="admin")
    expect(s, acc, (200,), "create merchant")
    profile = (acc or {}).get("default_profile")
    if not profile:
        s, profiles = client.call("GET", f"/account/{mid}/business_profile", key="admin")
        expect(s, profiles, (200,), "list profiles")
        profile = profiles[0]["profile_id"] if isinstance(profiles, list) and profiles else None
    if not profile:
        raise Failed("merchant has no profile")
    s, key = client.call("POST", f"/api_keys/{mid}", {"name": "ci", "expiration": "never"}, key="admin")
    expect(s, key, (200,), "create api key")
    s, mca = client.call("POST", f"/account/{mid}/connectors", {
        "connector_type": "payment_processor", "connector_name": connector, "profile_id": profile,
        "connector_account_details": {"auth_type": "HeaderKey", "api_key": secrets.token_hex(8)},
        "test_mode": True, "disabled": False, "payment_methods_enabled": [{"payment_method": "card"}]}, key="admin")
    expect(s, mca, (200,), "create connector")
    client.api_key = key["api_key"]
    return {"merchant_id": mid, "profile_id": profile}


def create_body(ctx, connector, payment_id=None):
    body = {"amount": live.AMOUNT, "currency": live.CURRENCY, "confirm": False, "capture_method": "automatic",
            "merchant_id": ctx["merchant_id"], "profile_id": ctx["profile_id"],
            "routing": {"type": "single", "data": connector}}
    if payment_id:
        body["payment_id"] = payment_id
    return body


def scenario_health(client, ctx, cfg):
    for url in [client.base + "/health", *cfg.get("health_urls", ())]:
        status, _ = Client(url).call("GET", "")
        if status != 200:
            raise Failed(f"health {urllib.parse.urlsplit(url).port or ''}: HTTP {status}")


def scenario_auth_required(client, ctx, cfg):
    s, out = Client(client.base).call("POST", "/payments", create_body(ctx, cfg["connector"]), key=None)
    expect(s, out, (401,), "create without api-key")
    error_contract(out)


def scenario_create_get_cancel(client, ctx, cfg):
    s, created = client.call("POST", "/payments", create_body(ctx, cfg["connector"]))
    expect(s, created, (200,), "create")
    payment_contract(created)
    if created["status"] != "requires_payment_method":
        raise Failed(f"create: status {created['status']!r}")
    pid = urllib.parse.quote(created["payment_id"], safe="")
    s, got = client.call("GET", f"/payments/{pid}")
    expect(s, got, (200,), "get")
    payment_contract(got)
    if got["payment_id"] != created["payment_id"] or got["amount"] != live.AMOUNT:
        raise Failed("get: does not match the created payment")
    s, cancelled = client.call("POST", f"/payments/{pid}/cancel", {"cancellation_reason": "ci"})
    expect(s, cancelled, (200,), "cancel")
    if cancelled.get("status") != "cancelled":
        raise Failed(f"cancel: status {cancelled.get('status')!r}")


def scenario_duplicate_payment_id(client, ctx, cfg):
    pid = "ci_dup_" + secrets.token_hex(6)
    s, first = client.call("POST", "/payments", create_body(ctx, cfg["connector"], pid))
    expect(s, first, (200,), "first create")
    s, second = client.call("POST", "/payments", create_body(ctx, cfg["connector"], pid))
    expect(s, second, (400, 409, 422), "duplicate create")
    error_contract(second)


def scenario_unknown_payment(client, ctx, cfg):
    s, out = client.call("GET", "/payments/pay_ci_" + secrets.token_hex(8))
    expect(s, out, (404,), "get unknown")
    error_contract(out)


def scenario_token_lifecycle(client, ctx, cfg):
    # the same request shapes as the live smoke: create, confirm, get, refund
    host = urllib.parse.urlsplit(client.base).hostname
    env = {"SMOKE_ROUTER_URL": client.base, "SMOKE_CELL": "ci", "SMOKE_CELL_HEADER": "x-ci-cell",
           "SMOKE_API_KEY": client.api_key, "SMOKE_MERCHANT_ID": ctx["merchant_id"], "SMOKE_PROFILE_ID": ctx["profile_id"],
           "SMOKE_CONNECTOR": cfg["connector"], "SMOKE_PAYMENT_METHOD_TOKEN": cfg["payment_token"]}
    lines = []
    if not live.Runner(env, allow_hosts=(host,)).lifecycle(lines.append):
        raise Failed("; ".join(x for x in lines if "FAIL" in x) or "lifecycle failed")


SCENARIOS = [
    ("health", scenario_health, None),
    ("auth-required", scenario_auth_required, None),
    ("create-get-cancel", scenario_create_get_cancel, None),
    ("duplicate-payment-id", scenario_duplicate_payment_id, None),
    ("unknown-payment", scenario_unknown_payment, None),
    ("token-lifecycle", scenario_token_lifecycle, "payment_token"),
]


def run_all(client, ctx, cfg, log, clock=time.monotonic):
    failed = 0
    for name, fn, needs in SCENARIOS:
        if needs and not cfg.get(needs):
            log(f"scenario {name}: skip (no {needs})")
            continue
        started = clock()
        try:
            fn(client, ctx, cfg)
        except Failed as err:
            failed += 1
            log(f"scenario {name}: FAIL {err}")
            continue
        log(f"scenario {name}: ok {clock() - started:.1f}s")
    return failed
