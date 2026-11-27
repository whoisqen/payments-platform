#!/usr/bin/env python3
# Runs every generator of tools/config in one go: `python3 tools/config/render [--check]` (make render, make lint-repo).
import subprocess
import sys
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[1]
GENERATORS = [
    "render_standby.py",
    "render_central.py",
    "render_victoria.py",
    "render/render_vmalert.py",
    "render_vault.py",
    "render_sentry.py",
    "render_grafana.py",
    "render_exporters.py",
    "render_otel.py",
    "render/render_admin_gateway.py",
    "render/render_admin_sso.py",
]


def main(argv):
    check = "--check" in argv
    failed = []
    for g in GENERATORS:
        code = subprocess.run([sys.executable, str(CONFIG / g), *(["--check"] if check else [])]).returncode
        if code:
            failed.append(g)
    for g in failed:
        print(f"render: {g} {'is out of date' if check else 'failed'}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
