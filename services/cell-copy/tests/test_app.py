import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app

SCHEMA = {
    "merchant_account": {"cols": ["merchant_id", "name"], "key": ["merchant_id"]},
    "payment_intent": {
        "cols": ["payment_id", "merchant_id", "amount"],
        "key": ["payment_id", "merchant_id"],
    },
}


class FakeCursor:
    def __init__(self, db):
        self.db, self.result = db, []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=()):
        if sql == app.TABLES_SQL:
            self.result = [(t,) for t in sorted(self.db.schema)]
        elif sql == app.COLUMNS_SQL:
            self.result = [(c,) for c in self.db.schema[params[0]]["cols"]]
        elif sql == app.KEY_SQL:
            self.result = [(c,) for c in self.db.schema[params[0]]["key"]]
        elif sql.startswith("SELECT"):
            table = sql.split("FROM public.")[1].split('"')[1]
            cols = self.db.schema[table]["cols"]
            m = cols.index("merchant_id")
            self.result = sorted(
                r for r in self.db.rows[table].values() if r[m] == params[0]
            )
        else:
            raise AssertionError(sql)

    def fetchall(self):
        return self.result

    def fetchmany(self, n):
        out, self.result = self.result[:n], self.result[n:]
        return out

    def executemany(self, sql, rows):
        assert sql.startswith("INSERT INTO public.") and "ON CONFLICT" in sql
        table = sql.split("INSERT INTO public.")[1].split('"')[1]
        s = self.db.schema[table]
        for r in rows:
            k = tuple(r[s["cols"].index(c)] for c in s["key"])
            self.db.pending[(table, k)] = r


class FakeDb:
    def __init__(self, rows=None):
        self.schema = SCHEMA
        self.rows = {t: {} for t in SCHEMA}
        for table, rs in (rows or {}).items():
            for r in rs:
                s = SCHEMA[table]
                self.rows[table][tuple(r[s["cols"].index(c)] for c in s["key"])] = r
        self.pending, self.read_only, self.closed = {}, False, False

    def cursor(self):
        return FakeCursor(self)

    def commit(self):
        for (table, k), r in self.pending.items():
            self.rows[table][k] = r
        self.pending = {}

    def rollback(self):
        self.pending = {}

    def close(self):
        self.closed = True


class FakeDriver:
    def __init__(self, dbs):
        self.dbs, self.calls = dbs, []

    def connect(self, **kw):
        self.calls.append(kw)
        return self.dbs[kw["host"]]


class FakeSecrets:
    def get_secret_value(self, SecretId):
        return {"SecretString": json.dumps({"username": "hs_app", "password": "x"})}


CELLS = {
    "cell-0": {"host": "p0", "secret": "s0"},
    "cell-1": {"host": "p1", "secret": "s1"},
}
SRC_ROWS = {
    "merchant_account": [("m1", "Shop"), ("m2", "Other")],
    "payment_intent": [("p1", "m1", 100), ("p2", "m1", 200), ("p3", "m2", 300)],
}


def run(action, src, dst, merchant="m1"):
    return app.run(
        {
            "action": action,
            "merchant": merchant,
            "source": "cell-0",
            "target": "cell-1",
        },
        CELLS,
        FakeSecrets(),
        FakeDriver({"p0": src, "p1": dst}),
    )


class CellCopy(unittest.TestCase):
    def test_copy_moves_only_the_merchant_and_is_idempotent(self):
        src, dst = FakeDb(SRC_ROWS), FakeDb()
        out = run("copy", src, dst)
        self.assertEqual(
            out,
            {
                "ok": True,
                "action": "copy",
                "rows": {"merchant_account": 1, "payment_intent": 2},
            },
        )
        self.assertEqual(
            sorted(dst.rows["payment_intent"].values()),
            [("p1", "m1", 100), ("p2", "m1", 200)],
        )
        self.assertEqual(run("copy", src, dst)["rows"]["payment_intent"], 2)
        self.assertEqual(len(dst.rows["payment_intent"]), 2)
        self.assertTrue(src.read_only and src.closed and dst.closed)

    def test_verify_passes_after_copy_and_finds_a_drift(self):
        src, dst = FakeDb(SRC_ROWS), FakeDb()
        self.assertFalse(run("verify", src, dst)["ok"])
        run("copy", src, dst)
        self.assertEqual(
            run("verify", src, dst), {"ok": True, "action": "verify", "differences": {}}
        )
        dst.rows["payment_intent"][("p1", "m1")] = ("p1", "m1", 999)
        out = run("verify", src, dst)
        self.assertFalse(out["ok"])
        self.assertEqual(list(out["differences"]), ["payment_intent"])

    def test_bad_requests_are_refused_before_any_connection(self):
        for event in (
            {
                "action": "drop",
                "merchant": "m1",
                "source": "cell-0",
                "target": "cell-1",
            },
            {
                "action": "copy",
                "merchant": "m1'; --",
                "source": "cell-0",
                "target": "cell-1",
            },
            {
                "action": "copy",
                "merchant": "m1",
                "source": "cell-0",
                "target": "cell-0",
            },
        ):
            driver = FakeDriver({})
            self.assertFalse(app.run(event, CELLS, FakeSecrets(), driver)["ok"])
            self.assertEqual(driver.calls, [])
        out = app.run(
            {
                "action": "copy",
                "merchant": "m1",
                "source": "cell-0",
                "target": "cell-9",
            },
            CELLS,
            FakeSecrets(),
            FakeDriver({"p0": FakeDb()}),
        )
        self.assertEqual(out, {"ok": False, "error": "unknown cell cell-9"})

    def test_connections_use_tls_and_the_proxy_login(self):
        driver = FakeDriver({"p0": FakeDb(SRC_ROWS), "p1": FakeDb()})
        app.run(
            {
                "action": "verify",
                "merchant": "m1",
                "source": "cell-0",
                "target": "cell-1",
            },
            CELLS,
            FakeSecrets(),
            driver,
        )
        self.assertTrue(
            all(
                c["sslmode"] == "require"
                and c["user"] == "hs_app"
                and c["port"] == 5432
                for c in driver.calls
            )
        )

    def test_sql_quotes_identifiers_and_upserts_on_the_key(self):
        sql = app.upsert_sql(
            "payment_intent",
            ["payment_id", "merchant_id", "amount"],
            ["payment_id", "merchant_id"],
        )
        self.assertIn(
            'ON CONFLICT ("payment_id", "merchant_id") DO UPDATE SET "amount" = EXCLUDED."amount"',
            sql,
        )
        with self.assertRaises(app.Refused):
            app.ident('x"; drop table y; --')
        with self.assertRaises(app.Refused):
            app.upsert_sql("no_key", ["merchant_id"], [])


if __name__ == "__main__":
    unittest.main()
