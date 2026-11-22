import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import miniyaml  # noqa: E402

HERE = Path(__file__).resolve().parent


def load(path):
    return miniyaml.loads(Path(path).read_text())


# Confirmed capacity wins; until the breakpoint test confirms the target, HPA works with the baseline.
def per_pod(comp, mode="in-use"):
    if mode == "target":
        return comp["target_per_pod"]
    if mode == "baseline":
        return comp["baseline_per_pod"]
    return comp.get("confirmed_per_pod") or comp["baseline_per_pod"]


def _ceil(x):
    return math.ceil(round(x, 9))


def replicas(cfg, forecast, mode="in-use"):
    cells = cfg["cells"]
    util = cfg["target_utilization"]
    result = {}
    for name, comp in cfg["components"].items():
        if "fixed_replicas" in comp:
            n = comp["fixed_replicas"]
            result[name] = {"scope": comp["scope"], "min": n, "max": n, "sale_pods": n * (cells if comp["scope"] == "cell" else 1)}
            continue
        divisor = cells if comp["scope"] == "cell" else 1
        usable = per_pod(comp, mode) * util
        daily = forecast["tps"]["daily_peak"] * comp["load_per_tps"] / divisor
        sale = forecast["tps"]["sale_peak"] * comp["load_per_tps"] / divisor
        result[name] = {
            "scope": comp["scope"],
            "per_pod": per_pod(comp, mode),
            "min": max(comp["min_floor"], _ceil(daily / usable)),
            "max": max(comp["min_floor"], _ceil(sale / usable * cfg["max_headroom"])),
            "sale_pods": _ceil(forecast["tps"]["sale_peak"] * comp["load_per_tps"] / usable),
        }
    return result


# A drop of confirmed capacity by more than the threshold is a regression and fails CI.
def regressions(old_cfg, new_cfg):
    threshold = new_cfg["regression_threshold"]
    found = []
    for name, old in old_cfg["components"].items():
        new = new_cfg["components"].get(name, {})
        if "fixed_replicas" in old:
            continue
        before, after = per_pod(old), per_pod(new) if new else 0
        if before and (before - after) / before > threshold:
            found.append({"component": name, "before": before, "after": after, "drop": round((before - after) / before, 3)})
    return found


def main(argv=None):
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("calc")
    c.add_argument("--capacity", default=str(HERE / "pod-capacity.yaml"))
    c.add_argument("--forecast", default=str(HERE / "forecast.yaml"))
    c.add_argument("--mode", choices=["in-use", "baseline", "target"], default="in-use")
    r = sub.add_parser("regression")
    r.add_argument("previous")
    r.add_argument("--capacity", default=str(HERE / "pod-capacity.yaml"))
    a = p.parse_args(argv)
    if a.cmd == "calc":
        print(json.dumps(replicas(load(a.capacity), load(a.forecast), a.mode), indent=2))
        return 0
    found = regressions(load(a.previous), load(a.capacity))
    print(json.dumps(found, indent=2))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
