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
