"""Copies or verifies one merchant's rows between two cell databases.

Invoked by the SSM Automation documents cell-copy-merchant and cell-verify-merchant (infra/modules/cell-migration) with
{"action": "copy" | "verify", "merchant": "<merchant_id>", "source": "<cell>", "target": "<cell>"}; answers {"ok": true, ...}.

copy: every table of the public schema that has a merchant_id column is copied for that merchant in one transaction on the
target, as an upsert on the primary key, so a repeated copy (copy-delta) brings the target up to date.
verify: for every such table the row count and an order-independent checksum of the rows must match on both sides.
The cells come from CELLS (JSON {cell: {host, secret}}); each secret holds the RDS Proxy login {username, password}.
"""

import hashlib
import json
import os
import re

DATABASE = os.environ.get("DATABASE", "hyperswitch")
MERCHANT = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
IDENT = re.compile(r"^[a-z_][a-z0-9_]{0,62}$")
BATCH = 1000

TABLES_SQL = """
SELECT c.table_name
FROM information_schema.columns c
JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
WHERE c.table_schema = 'public' AND c.column_name = 'merchant_id' AND t.table_type = 'BASE TABLE'
ORDER BY c.table_name
"""

COLUMNS_SQL = """
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = %s AND is_generated = 'NEVER'
ORDER BY ordinal_position
"""

KEY_SQL = """
SELECT a.attname FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
WHERE i.indrelid = ('public.' || quote_ident(%s))::regclass AND i.indisprimary
ORDER BY array_position(i.indkey, a.attnum)
"""


class Refused(Exception):
    pass


def ident(name):
    # Names come from the catalog, but only plain lower-case identifiers are ever interpolated into SQL
    if not IDENT.match(name):
        raise Refused(f"unexpected identifier {name!r}")
    return '"' + name + '"'


def parse(event):
    action, merchant = event.get("action"), event.get("merchant", "")
    source, target = event.get("source", ""), event.get("target", "")
    if action not in ("copy", "verify"):
        raise Refused("action must be copy or verify")
    if not MERCHANT.match(merchant):
        raise Refused("merchant id is not valid")
    if not source or source == target:
        raise Refused("source and target must be two different cells")
    return action, merchant, source, target


def tables(cur):
    cur.execute(TABLES_SQL)
    return [r[0] for r in cur.fetchall()]


def columns(cur, table):
    cur.execute(COLUMNS_SQL, (table,))
    return [r[0] for r in cur.fetchall()]


def primary_key(cur, table):
    cur.execute(KEY_SQL, (table,))
    return [r[0] for r in cur.fetchall()]


def upsert_sql(table, cols, key):
    names = ", ".join(ident(c) for c in cols)
    marks = ", ".join(["%s"] * len(cols))
    update = [c for c in cols if c not in key]
    if not key:
        raise Refused(
            f"table {table} has no primary key, so a repeated copy cannot be idempotent"
        )
    conflict = ", ".join(ident(c) for c in key)
    action = (
        "DO NOTHING"
        if not update
        else "DO UPDATE SET "
        + ", ".join(f"{ident(c)} = EXCLUDED.{ident(c)}" for c in update)
    )
    return f"INSERT INTO public.{ident(table)} ({names}) VALUES ({marks}) ON CONFLICT ({conflict}) {action}"


def select_sql(table, cols, key):
    order = ", ".join(ident(c) for c in key) or "1"
    return f"SELECT {', '.join(ident(c) for c in cols)} FROM public.{ident(table)} WHERE merchant_id = %s ORDER BY {order}"


def copy(src, dst, merchant):
    copied = {}
    with src.cursor() as s, dst.cursor() as d:
        for table in tables(s):
            cols, key = columns(s, table), primary_key(s, table)
            sql = upsert_sql(table, cols, key)
            s.execute(select_sql(table, cols, key), (merchant,))
            n = 0
            while rows := s.fetchmany(BATCH):
                d.executemany(sql, rows)
                n += len(rows)
            copied[table] = n
    dst.commit()
    return copied


def digest(cur, table, merchant):
    cols, key = columns(cur, table), primary_key(cur, table)
    cur.execute(select_sql(table, cols, key), (merchant,))
    h, n = hashlib.sha256(), 0
    while rows := cur.fetchmany(BATCH):
        for row in rows:
            h.update(repr(tuple(row)).encode())
            n += 1
    return n, h.hexdigest()


def verify(src, dst, merchant):
    diff = {}
    with src.cursor() as s, dst.cursor() as d:
        for table in tables(s):
            a, b = digest(s, table, merchant), digest(d, table, merchant)
            if a != b:
                diff[table] = {"source_rows": a[0], "target_rows": b[0]}
    return diff


def connect(cells, cell, secrets, driver):
    if cell not in cells:
        raise Refused(f"unknown cell {cell}")
    login = json.loads(
        secrets.get_secret_value(SecretId=cells[cell]["secret"])["SecretString"]
    )
    return driver.connect(
        host=cells[cell]["host"],
        port=5432,
        dbname=DATABASE,
        user=login["username"],
        password=login["password"],
        sslmode="require",
        connect_timeout=10,
    )


def run(event, cells, secrets, driver):
    try:
        action, merchant, source, target = parse(event)
        src, dst = (
            connect(cells, source, secrets, driver),
            connect(cells, target, secrets, driver),
        )
    except Refused as err:
        return {"ok": False, "error": str(err)}
    try:
        src.read_only = True
        if action == "copy":
            return {"ok": True, "action": action, "rows": copy(src, dst, merchant)}
        diff = verify(src, dst, merchant)
        return {"ok": not diff, "action": action, "differences": diff}
    except Refused as err:
        dst.rollback()
        return {"ok": False, "error": str(err)}
    finally:
        src.close()
        dst.close()


def handler(event, context):  # pragma: no cover - wiring of the real clients
    import boto3
    import psycopg

    return run(
        event, json.loads(os.environ["CELLS"]), boto3.client("secretsmanager"), psycopg
    )
