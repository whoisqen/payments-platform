import copy
import json
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
DEPLOY = REPO / "deploy"
CHARTS = DEPLOY / "charts"
ENVS = DEPLOY / "envs"
FIXTURE_DIGEST = "sha256:" + "0" * 64
UNLAYERED = {"edge", "control-center"}


def load_yaml(path):
    return yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def merge(base, over):
    out = copy.deepcopy(base)
    for k, v in over.items():
        out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else copy.deepcopy(v)
    return out


def chart_for(release):
    if release.startswith("cell-") or release == "spare":
        return "payments-cell"
    return {"edge": "payments-edge", "locker": "payments-locker", "control-center": "control-center"}[release]


def environments():
    return sorted(p.name for p in ENVS.iterdir() if p.is_dir())


def regions(env):
    return sorted(p.name for p in (ENVS / env).iterdir() if p.is_dir())


def releases(env, region):
    return sorted(p.name for p in (ENVS / env / region).iterdir() if p.is_dir())


def layered(env, region, release):
    # chart defaults, then env, region and release layers, as the ApplicationSet orders them
    chart = chart_for(release)
    vals = load_yaml(CHARTS / chart / "values.yaml") if (CHARTS / chart / "values.yaml").is_file() else {}
    layers = (ENVS / env / "values.yaml", ENVS / env / region / "values.yaml", ENVS / env / region / release / "values.yaml")
    if release in UNLAYERED:
        layers = layers[2:]
    for f in layers:
        vals = merge(vals, load_yaml(f))
    return chart, vals


def dependencies(chart):
    deps = load_yaml(CHARTS / chart / "Chart.yaml").get("dependencies", [])
    return [(d.get("alias", d["name"]), d["name"]) for d in deps]


def with_digest(vals):
    # image.digest comes from images.yaml in CI; a fixture digest stands in offline
    out = copy.deepcopy(vals)
    out.setdefault("image", {}).setdefault("digest", FIXTURE_DIGEST)
    return out


def schema_targets(env, region, release):
    # yields (label, chart, values) for the release chart and each subchart with its merged subtree
    chart, vals = layered(env, region, release)
    label = f"{env}/{region}/{release}"
    if chart != "control-center":
        yield label, chart, vals
    for alias, sub in dependencies(chart):
        if not (CHARTS / sub / "values.schema.json").is_file():
            continue
        subvals = load_yaml(CHARTS / sub / "values.yaml")
        subvals = merge(subvals, vals.get(alias, {}))
        subvals = merge(subvals, {"global": vals.get("global", {})})
        yield f"{label}:{alias}", sub, with_digest(subvals)
    if chart == "control-center":
        yield label, chart, with_digest(vals)
