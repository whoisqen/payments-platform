import itertools
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "pm_" + "fake_tok"


def _err(code, kind, message):
    return {"error": {"type": kind, "message": message, "code": code}}


class State:
    def __init__(self, admin_key, faults=()):
        self.admin_key, self.faults = admin_key, set(faults)
        self.keys, self.payments, self.idem = {}, {}, {}
        self.ids = itertools.count(1)

    def handle(self, method, path, body, headers):
        parts = [p for p in path.split("?")[0].split("/") if p]
        key = headers.get("api-key")
        if parts == ["health"]:
            return 200, {}
        if parts[:1] in (["accounts"], ["api_keys"], ["account"]):
            if key != self.admin_key:
                return 401, _err("IR_01", "invalid_request", "admin key")
            return self.admin(method, parts, body)
        if key not in self.keys and "no_auth" not in self.faults:
            return 401, _err("IR_01", "invalid_request", "api key")
        return self.payment(method, parts, body, headers)

    def admin(self, method, parts, body):
        if parts == ["accounts"]:
            return 200, {"merchant_id": body["merchant_id"], "default_profile": "pro_" + body["merchant_id"]}
        if parts[0] == "api_keys":
            k = f"snd_fake_{next(self.ids)}"
            self.keys[k] = parts[1]
            return 200, {"api_key": k}
        if parts[2:] == ["connectors"]:
            return 200, {"merchant_connector_id": "mca_1", "connector_name": body["connector_name"]}
        return 404, _err("HE_02", "object_not_found", "route")

    def payment(self, method, parts, body, headers):
        if method == "POST" and parts == ["payments"]:
            idem = headers.get("idempotency-key")
            if idem in self.idem:
                return 200, self.payments[self.idem[idem]]
            pid = body.get("payment_id") or f"pay_{next(self.ids)}"
            if pid in self.payments and "dup_ok" not in self.faults:
                return 400, _err("HE_01", "invalid_request", "duplicate payment")
            p = {"payment_id": pid, "status": "requires_payment_method", "amount": body["amount"], "currency": body["currency"]}
            if "bad_shape" in self.faults:
                p.pop("currency")
            self.payments[pid] = p
            if idem:
                self.idem[idem] = pid
            return 200, p
        if method == "POST" and parts == ["refunds"]:
            p = self.payments.get(body.get("payment_id"))
            if not p or p["status"] != "succeeded":
                return 400, _err("IR_14", "invalid_request", "state")
            return 200, {"refund_id": "ref_1", "status": "succeeded", "payment_id": p["payment_id"]}
        p = self.payments.get(parts[1]) if len(parts) >= 2 and parts[0] == "payments" else None
        if p is None:
            return 404, _err("HE_02", "object_not_found", "payment")
        if method == "GET" and len(parts) == 2:
            return 200, p
        if method == "POST" and parts[2:] == ["cancel"]:
            if "cancel_noop" not in self.faults:
                p["status"] = "cancelled"
            return 200, p
        if method == "POST" and parts[2:] == ["confirm"]:
            p["status"] = "succeeded" if body.get("payment_token") == TOKEN else "failed"
            return 200, p
        return 400, _err("IR_14", "invalid_request", "state")


def serve(state):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _do(self):
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n) or b"{}")
            status, out = state.handle(self.command, self.path, body, {k.lower(): v for k, v in self.headers.items()})
            raw = json.dumps(out).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        do_GET = do_POST = _do

    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv
