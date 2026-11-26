#!/usr/bin/env python3
"""Component check: start each service binary, wait for its health endpoints, then stop it with SIGTERM.

  python3 tests/component/run.py router drainer [--root DIR] [--timeout 120] [--logs DIR]

The binary path comes from COMPONENT_<NAME>_BIN; a service without one is reported and skipped,
so a job that built only one workspace checks only its own services.
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from component import harness, services  # noqa: E402


def check(name, root, values, timeout, logs, environ, grace=15.0):
    spec = services.SPECS[name]
    binary = environ.get(spec["bin_env"])
    if not binary:
        return "skip", f"{spec['bin_env']} is not set"
    log_path = os.path.join(logs, f"{name}.log") if logs else os.devnull
    svc = harness.Service(name, [binary, *spec["args"]], services.render(name, values), cwd=os.path.join(root, spec["cwd"]), log_path=log_path)
    base = f"http://127.0.0.1:{spec['port']}"
    with svc:
        try:
            for path in spec["health"]:
                harness.wait_healthy(base + path, timeout, proc=svc.proc)
            code = svc.stop(grace)
        except harness.ServiceError as err:
            return "fail", str(err)
    if code not in (0, -15, 143):
        return "fail", f"exit code {code} after SIGTERM"
    return "ok", ", ".join(spec["health"])


def main(argv=None, environ=None):
    environ = os.environ if environ is None else environ
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+", choices=sorted(services.SPECS))
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--logs", default="")
    ns = ap.parse_args(argv)
    if ns.logs:
        os.makedirs(ns.logs, exist_ok=True)
    values = services.runtime(environ)
    failed = 0
    for name in ns.names:
        status, detail = check(name, ns.root, values, ns.timeout, ns.logs, environ)
        print(f"component {name}: {status} ({detail})")
        failed += status == "fail"
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
