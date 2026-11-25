#!/usr/bin/env python3
"""API integration scenarios against a running router with the dummy connector.

  python3 tests/integration/run.py [--skip-unset]

Environment: INTEGRATION_API_URL; either INTEGRATION_ADMIN_API_KEY (a merchant, key and dummy connector
are created) or INTEGRATION_API_KEY, INTEGRATION_MERCHANT_ID and INTEGRATION_PROFILE_ID; optional
INTEGRATION_CONNECTOR, INTEGRATION_PAYMENT_TOKEN, INTEGRATION_HEALTH_URLS (comma separated) and
INTEGRATION_COMPOSE_HOSTS. Output names steps and status codes only, never keys or bodies.
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from integration import api  # noqa: E402
from smoke import live  # noqa: E402


def main(argv=None, environ=None, out=None):
    e = os.environ if environ is None else environ
    out = sys.stdout if out is None else out
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-unset", action="store_true", help="exit 0 when INTEGRATION_API_URL is not set")
    ns = ap.parse_args(argv)

    def log(line):
        print(line, file=out, flush=True)

    url = e.get("INTEGRATION_API_URL", "")
    if not url:
        log("integration: INTEGRATION_API_URL is not set")
        return 0 if ns.skip_unset else 2
    connector = e.get("INTEGRATION_CONNECTOR", "pretendpay")
    if connector not in live.DUMMY_CONNECTORS:
        log("integration refused: connector is not a dummy connector")
        return 2
    compose = tuple(h for h in e.get("INTEGRATION_COMPOSE_HOSTS", "").split(",") if h)
    health = [u for u in e.get("INTEGRATION_HEALTH_URLS", "").split(",") if u]
    try:
        for u in [url, *health]:
            api.check_url(u, compose)
    except ValueError as err:
        log(f"integration refused: {err}")
        return 2
    client = api.Client(url, api_key=e.get("INTEGRATION_API_KEY"), admin_key=e.get("INTEGRATION_ADMIN_API_KEY"))
    try:
        if client.admin_key:
            ctx = api.bootstrap(client, connector)
            log("bootstrap: ok")
        else:
            ctx = {"merchant_id": e.get("INTEGRATION_MERCHANT_ID", ""), "profile_id": e.get("INTEGRATION_PROFILE_ID", "")}
            if not (client.api_key and ctx["merchant_id"] and ctx["profile_id"]):
                log("integration refused: set INTEGRATION_ADMIN_API_KEY or the API key, merchant and profile")
                return 2
    except api.Failed as err:
        log(f"bootstrap: FAIL {err}")
        return 1
    cfg = {"connector": connector, "payment_token": e.get("INTEGRATION_PAYMENT_TOKEN", ""), "health_urls": health}
    failed = api.run_all(client, ctx, cfg, log)
    log(f"integration: {len(api.SCENARIOS)} scenario(s), {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
