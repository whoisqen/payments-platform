import argparse
import json
import operator
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from guard import may_run  # noqa: E402

OPS = {"<": operator.lt, "<=": operator.le, ">": operator.gt, ">=": operator.ge, "==": operator.eq}


def load(path):
    return json.loads(Path(path).read_text())


def holds(cond, metrics):
    return OPS[cond["op"]](metrics[cond["metric"]], cond["value"])


def topo_order(steps):
    done, order = set(), []
    while len(order) < len(steps):
        ready = [s for s in steps if s["id"] not in done and all(a in done for a in s["after"])]
        if not ready:
            raise ValueError("steps have a cycle or an unknown dependency")
        for s in ready:
            done.add(s["id"])
            order.append(s)
    return order


# Earliest finish of every step in minutes, assuming each step takes exactly its budget.
def timeline(scenario, overrun=None):
    overrun = overrun or {}
    finish = {}
    for s in topo_order(scenario["steps"]):
        start = max((finish[a] for a in s["after"]), default=0)
        finish[s["id"]] = start + s["budget_min"] + overrun.get(s["id"], 0)
    return finish


def rto_minutes(scenario, overrun=None):
    finish = timeline(scenario, overrun)
    return max(finish[s["id"]] for s in scenario["steps"] if not s.get("post_rto"))


def validate(scenario):
    errors = []
    ids = [s["id"] for s in scenario["steps"]]
    if len(set(ids)) != len(ids):
        errors.append("duplicate step ids")
    try:
        topo_order(scenario["steps"])
    except ValueError as e:
        return errors + [str(e)]
    pnr = [s["id"] for s in scenario["steps"] if s.get("point_of_no_return")]
    if pnr != ["promote-aurora"]:
        errors.append("exactly one point of no return is allowed and it is promote-aurora")
    by_id = {s["id"]: s for s in scenario["steps"]}
    if "fence-frankfurt" not in _ancestors(by_id, "promote-aurora"):
        errors.append("promote-aurora must come after fence-frankfurt (one writer only)")
    metrics = set(scenario["metrics"])
    for kind in ("preconditions", "steady_state", "abort_conditions"):
        for c in scenario[kind]:
            if c["metric"] not in metrics or c["op"] not in OPS:
                errors.append(f"{kind}: bad metric or operator in {c.get('id', c['metric'])}")
    for c in scenario["abort_conditions"]:
        if c["when_before"] not in by_id:
            errors.append(f"abort {c['id']}: unknown step {c['when_before']}")
    if not scenario["steady_state"] or not scenario["abort_conditions"]:
        errors.append("a scenario needs steady-state hypotheses and abort conditions")
    if rto_minutes(scenario) > scenario["rto_target_min"]:
        errors.append(f"critical path {rto_minutes(scenario)} min exceeds the RTO target {scenario['rto_target_min']} min")
    return errors


def _ancestors(by_id, step_id):
    seen, stack = set(), list(by_id[step_id]["after"])
    while stack:
        s = stack.pop()
        if s not in seen:
            seen.add(s)
            stack.extend(by_id[s]["after"])
    return seen


# Before the point of no return a tripped condition aborts and un-fences Frankfurt; after it the run can only halt and escalate.
def evaluate_abort(scenario, metrics, next_step):
    order = [s["id"] for s in topo_order(scenario["steps"])]
    pnr_index = order.index("promote-aurora")
    outcomes = []
    for c in scenario["abort_conditions"]:
        if order.index(next_step) > order.index(c["when_before"]):
            continue
        if holds(c, metrics):
            outcomes.append((c["id"], "abort" if order.index(next_step) <= pnr_index else "halt-escalate"))
    return outcomes


def evaluate_steady_state(scenario, metrics):
    return {c["id"]: holds(c, metrics) for c in scenario["steady_state"]}


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("scenario")
    p.add_argument("--dry-run", action="store_true", required=True)
    p.add_argument("--context", default='{"environment": "stage", "freeze": false, "open_incidents": 0}')
    a = p.parse_args(argv)
    ok, reasons = may_run(json.loads(a.context))
    if not ok:
        print("refused: " + "; ".join(reasons))
        return 2
    sc = load(a.scenario)
    errors = validate(sc)
    for e in errors:
        print("invalid: " + e)
    if errors:
        return 1
    finish = timeline(sc)
    for sid, t in sorted(finish.items(), key=lambda kv: kv[1]):
        print(f"{t:3d} min  {sid}")
    print(f"RTO {rto_minutes(sc)} min of target {sc['rto_target_min']} min")
    return 0


if __name__ == "__main__":
    sys.exit(main())
