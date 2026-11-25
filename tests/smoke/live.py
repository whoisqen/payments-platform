"""Live smoke: create -> confirm -> get -> refund through the cell router, dummy connector only.

Run as `python -m smoke.live` from tests/. Reads only SMOKE_* environment variables and
no files; standard library only. Output is step names, status codes and error classes,
never credentials or response bodies.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

REQUIRED = ("SMOKE_ROUTER_URL", "SMOKE_CELL", "SMOKE_CELL_HEADER", "SMOKE_API_KEY", "SMOKE_MERCHANT_ID",
            "SMOKE_PROFILE_ID", "SMOKE_CONNECTOR", "SMOKE_PAYMENT_METHOD_TOKEN")
DUMMY_CONNECTORS = ("dummy", "fauxpay", "pretendpay", "phonypay", "stripe_test")
LOCAL_SUFFIXES = (".svc", ".svc.cluster.local")
MAX_BUDGET = 90.0
CALL_TIMEOUT = 20.0
AMOUNT, REFUND_AMOUNT, CURRENCY = 1000, 500, "EUR"


class StepFailed(Exception):
    pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    # a redirect would carry the api-key to another host
    def redirect_request(self, *args, **kwargs):
        return None


def _opener():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect)


def check_host(url, allow_hosts=()):
    p = urllib.parse.urlsplit(url)
    host = (p.hostname or "").lower()
    if p.scheme not in ("http", "https") or p.username or p.password:
        raise ValueError("router URL must be http(s) without credentials")
    if host in allow_hosts:
        return
    if not any(host.endswith(s) and len(host) > len(s) for s in LOCAL_SUFFIXES):
        raise ValueError("router host is not cluster-local (.svc or .svc.cluster.local)")


class Runner:
    def __init__(self, env, allow_hosts=()):
        missing = [k for k in REQUIRED if not env.get(k)]
        if missing:
            raise ValueError("missing environment: " + ", ".join(missing))
        self.base = env["SMOKE_ROUTER_URL"].rstrip("/")
        check_host(self.base, allow_hosts)
        if env["SMOKE_CONNECTOR"] not in DUMMY_CONNECTORS:
            raise ValueError("connector is not a dummy connector")
        try:
            budget = float(env.get("SMOKE_TIMEOUT_SECONDS") or MAX_BUDGET)
        except ValueError:
            raise ValueError("SMOKE_TIMEOUT_SECONDS is not a number") from None
        if budget <= 0:
            raise ValueError("SMOKE_TIMEOUT_SECONDS must be positive")
        self.deadline = time.monotonic() + min(budget, MAX_BUDGET)
        self.env = env
        self.run_id = uuid.uuid4().hex
        self.opener = _opener()

    def call(self, step, method, path, body=None, idempotent=False):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise StepFailed("time budget exhausted")
        e = self.env
        headers = {"Content-Type": "application/json", "api-key": e["SMOKE_API_KEY"], e["SMOKE_CELL_HEADER"]: e["SMOKE_CELL"]}
        if idempotent:
            headers["Idempotency-Key"] = f"smoke-{self.run_id}-{step}"
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=min(CALL_TIMEOUT, remaining)) as r:
                status, raw = r.status, r.read(1 << 20)
        except urllib.error.HTTPError as err:
            raise StepFailed(f"HTTP {err.code}") from None
        except Exception as err:  # the message may hold the URL, keep the class only
            raise StepFailed(f"request error {type(err).__name__}") from None
        if status not in (200, 201):
            raise StepFailed(f"HTTP {status}")
        try:
            out = json.loads(raw)
        except ValueError:
            raise StepFailed("response is not JSON") from None
        if not isinstance(out, dict):
            raise StepFailed("response is not an object")
        return out

    def lifecycle(self, log):
        e = self.env
        steps = []

        def step(name, fn):
            try:
                out = fn()
            except StepFailed as err:
                log(f"step {name}: FAIL {err}")
                steps.append(name)
                return None
            log(f"step {name}: ok")
            return out

        created = step("create", lambda: self.call("create", "POST", "/payments", {
            "amount": AMOUNT, "currency": CURRENCY, "confirm": False, "capture_method": "automatic",
            "merchant_id": e["SMOKE_MERCHANT_ID"], "profile_id": e["SMOKE_PROFILE_ID"],
            "routing": {"type": "single", "data": e["SMOKE_CONNECTOR"]}}, idempotent=True))
        pid = (created or {}).get("payment_id") or (created or {}).get("id")
        if created is not None and not isinstance(pid, str):
            log("step create: FAIL no payment id")
            return False
        if created is None:
            return False

        def expect(name, out, wanted):
            if out.get("status") not in wanted:
                raise StepFailed(f"unexpected status {out.get('status')!r}")
            return out

        quoted = urllib.parse.quote(pid, safe="")
        ok = step("confirm", lambda: expect("confirm", self.call(
            "confirm", "POST", f"/payments/{quoted}/confirm", {"payment_token": e["SMOKE_PAYMENT_METHOD_TOKEN"]}, idempotent=True),
            ("succeeded",)))
        if ok is None:
            return False
        ok = step("get", lambda: expect("get", self.call("get", "GET", f"/payments/{quoted}"), ("succeeded",)))
        if ok is None:
            return False
        ok = step("refund", lambda: expect("refund", self.call(
            "refund", "POST", "/refunds", {"payment_id": pid, "amount": REFUND_AMOUNT}, idempotent=True),
            ("succeeded", "pending")))
        return ok is not None


def main(env=None, err=None, allow_hosts=()):
    env = os.environ if env is None else env
    err = sys.stderr if err is None else err

    def log(line):
        print(line, file=err)

    try:
        runner = Runner(env, allow_hosts)
    except ValueError as exc:
        log(f"smoke refused: {exc}")
        return 1
    return 0 if runner.lifecycle(log) else 1


if __name__ == "__main__":
    sys.exit(main())
