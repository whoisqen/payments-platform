import itertools

TOKEN = "pm_synthetic_token"


class TestPsp:
    # the test PSP: approves the synthetic token, declines anything else
    def authorize(self, token, amount):
        return "approved" if token == TOKEN and amount > 0 else "declined"


class FakeCell:
    def __init__(self, name, host):
        self.name, self.host = name, host
        self.psp = TestPsp()
        self.payments = {}
        self.keys = {}
        self.ids = itertools.count(1)

    def handle(self, method, path, body, headers):
        parts = [p for p in path.split("/") if p]
        if method == "POST" and parts == ["payments"]:
            key = headers.get("idempotency-key")
            if key in self.keys:
                return 200, self.payments[self.keys[key]]
            if self.psp.authorize(body.get("payment_method_token"), body.get("amount", 0)) != "approved":
                return 402, {"status": "failed"}
            pid = f"pay_{self.name}_{next(self.ids)}"
            self.payments[pid] = {"id": pid, "cell": self.name, "status": "requires_capture", "amount": body["amount"], "refunded": 0}
            if key:
                self.keys[key] = pid
            return 201, self.payments[pid]
        pay = self.payments.get(parts[1]) if len(parts) >= 2 and parts[0] == "payments" else None
        if pay is None:
            return 404, {"error": "not_found"}
        if method == "POST" and parts[2:] == ["capture"] and pay["status"] == "requires_capture":
            pay["status"] = "succeeded"
        elif method == "POST" and parts[2:] == ["refund"] and pay["status"] == "succeeded":
            pay["refunded"] = pay["amount"]
            pay["status"] = "refunded"
        elif method == "GET" and len(parts) == 2:
            pass
        else:
            return 409, {"error": "invalid_state", "status": pay["status"]}
        return 200, pay


class FakeEdge:
    def __init__(self, values, cells=None):
        self.header = values["routing"]["cellHeader"]
        self.routes = {c["name"]: c["host"] for c in values["routing"]["cells"]}
        self.hosts = set(values["gateway"]["hosts"])
        self.cells = cells if cells is not None else {n: FakeCell(n, h) for n, h in self.routes.items()}

    def request(self, host, method, path, body=None, headers=None):
        headers = {k.lower(): v for k, v in (headers or {}).items()}
        if host not in self.hosts:
            return 404, {"error": "unknown_host"}
        name = headers.get(self.header)
        if name not in self.routes:
            return 421, {"error": "no_cell"}
        return self.cells[name].handle(method, path, body or {}, headers)
