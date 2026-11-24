ALLOWED_ENVIRONMENTS = {"stage"}


# Chaos never runs in prod or the CDE, during a freeze or with an open incident.
def may_run(ctx):
    reasons = []
    if ctx.get("environment") not in ALLOWED_ENVIRONMENTS:
        reasons.append(f"environment {ctx.get('environment')!r} is not allowed")
    if ctx.get("freeze"):
        reasons.append("change freeze is active")
    if ctx.get("open_incidents", 0) > 0:
        reasons.append("an incident is open")
    return (not reasons, reasons)


# k6 scenarios cannot call Python, so run this first: `python3 guard.py stage --open-incidents 0`.
def main(argv=None):
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("environment")
    p.add_argument("--freeze", action="store_true")
    p.add_argument("--open-incidents", type=int, default=0)
    a = p.parse_args(argv)
    ok, reasons = may_run({"environment": a.environment, "freeze": a.freeze, "open_incidents": a.open_incidents})
    for r in reasons:
        print(f"refused: {r}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
