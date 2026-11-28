#!/usr/bin/env python3
# Changed terragrunt stacks of one environment in dependency order; offline, so the order is tested without terragrunt.
import argparse
import json
import posixpath
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LIVE = "infra/live"
APPLY_ENVS = ("dev", "stage", "prod")
STACK_PATH = re.compile(r"^infra/live/(dev|stage|prod)/[a-z0-9-]+(/[a-z0-9-]+){1,2}$")
REPO_REF = re.compile(r"get_repo_root\(\)\}/([A-Za-z0-9_./-]+)")
ENVCOMMON_REF = re.compile(r"/_envcommon/([A-Za-z0-9_./-]+\.hcl)")
DEP_BLOCK = re.compile(r"config_path\s*=\s*\"([^\"]+)\"")
DEPS_PATHS = re.compile(r"dependencies\s*\{[^}]*?paths\s*=\s*\[([^\]]*)\]", re.S)
LOCAL_DEF = re.compile(r"^\s*([a-z_][a-z0-9_]*)\s*=\s*(.+?)\s*$", re.M)
INTERP = re.compile(r"\$\{([^}]+)\}")


class StackError(Exception):
    pass


def cfg_lookup(cfg, dotted):
    node = cfg
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            raise StackError(f"config/platform.yaml has no {dotted}")
        node = node[part]
    if not isinstance(node, str):
        raise StackError(f"config/platform.yaml {dotted} is not a string")
    return node


def resolve(expr, text, cfg):
    def one(m):
        ref = m.group(1).strip()
        if ref.startswith("local.cfg."):
            return cfg_lookup(cfg, ref[len("local.cfg."):])
        if ref.startswith("local."):
            name = ref[len("local."):]
            for d in LOCAL_DEF.finditer(text):
                if d.group(1) != name:
                    continue
                value = d.group(2)
                if value.startswith('"') and value.endswith('"') and "${" not in value:
                    return value[1:-1]
                hit = re.search(r"\.cfg\.([a-z0-9_.]+)$", value)
                if hit:
                    return cfg_lookup(cfg, hit.group(1))
            raise StackError(f"cannot resolve ${{{ref}}}")
        raise StackError(f"cannot resolve ${{{ref}}}")

    return INTERP.sub(one, expr)


def read(root, rel):
    p = Path(root) / rel
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def discover(root, env):
    base = Path(root) / LIVE / env
    if not base.is_dir():
        return []
    return sorted(p.parent.relative_to(root).as_posix() for p in base.rglob("terragrunt.hcl")
                  if ".terragrunt-cache" not in p.parts)


def envcommon_files(root, text):
    seen, todo = [], [m.group(1) for m in ENVCOMMON_REF.finditer(text)]
    while todo:
        rel = f"{LIVE}/_envcommon/{todo.pop(0)}"
        if rel in seen:
            continue
        seen.append(rel)
        todo += [m.group(1) for m in ENVCOMMON_REF.finditer(read(root, rel))]
    return seen


def module_closure(root, module_dir):
    seen, todo = set(), [module_dir.rstrip("/")]
    while todo:
        d = todo.pop()
        if d in seen:
            continue
        seen.add(d)
        for tf in (Path(root) / d).glob("*.tf"):
            for m in re.finditer(r"source\s*=\s*\"(\.\.?/[^\"]+)\"", tf.read_text(encoding="utf-8")):
                todo.append(posixpath.normpath(posixpath.join(d, m.group(1))))
    return seen


def parse_stack(root, stack, cfg):
    own = read(root, f"{stack}/terragrunt.hcl")
    commons = envcommon_files(root, own)
    texts = [own] + [read(root, c) for c in commons]
    env = stack.split("/")[2]
    inputs = {f"{stack}/terragrunt.hcl", f"{LIVE}/terragrunt.hcl", f"{LIVE}/{env}/env.hcl", *commons}
    for t in texts + [read(root, f"{LIVE}/{env}/env.hcl")]:
        for m in REPO_REF.finditer(t):
            ref = re.sub(r"/+", "/", m.group(1)).rstrip("/")
            if ref.startswith("infra/modules/"):
                inputs |= module_closure(root, ref)
            else:
                inputs.add(ref)
    deps = set()
    for t in texts:
        raw = [m.group(1) for m in DEP_BLOCK.finditer(t)]
        for m in DEPS_PATHS.finditer(t):
            raw += re.findall(r"\"([^\"]+)\"", m.group(1))
        for r in raw:
            # A path from the repository root names a stack of another root (for example the hub of shared-services)
            if r.startswith("${get_repo_root()}/"):
                deps.add(posixpath.normpath(resolve(r[len("${get_repo_root()}/"):], own, cfg)))
                continue
            deps.add(posixpath.normpath(posixpath.join(stack, resolve(r, own, cfg))))
    return {"dir": stack, "inputs": sorted(inputs), "deps": sorted(deps)}


def touches(inputs, changed):
    for f in changed:
        for i in inputs:
            if f == i or f.startswith(i + "/"):
                return True
    return False


def changed_stacks(graph, changed_files):
    return {s["dir"] for s in graph.values() if touches([s["dir"], *s["inputs"]], changed_files)}


def levels(graph, selected):
    remaining, done, out = set(selected), set(), []
    while remaining:
        ready = sorted(s for s in remaining if all(d in done or d not in remaining for d in graph[s]["deps"]))
        if not ready:
            raise StackError(f"dependency cycle among {sorted(remaining)}")
        out.append(ready)
        done |= set(ready)
        remaining -= set(ready)
    return out


def validate_stack(stack, root=ROOT):
    if not STACK_PATH.match(stack or "") or ".." in stack.split("/"):
        raise StackError(f"not an apply stack path: {stack!r}")
    if not (Path(root) / stack / "terragrunt.hcl").is_file():
        raise StackError(f"{stack} has no terragrunt.hcl")
    return stack


def git_changed(root, base, head):
    out = subprocess.run(["git", "diff", "--name-only", base, head], cwd=root, capture_output=True, text=True, check=True)
    return [line for line in out.stdout.splitlines() if line]


def load_cfg(root):
    import yaml

    return yaml.safe_load(read(root, "config/platform.yaml")) or {}


def build(root, env, cfg, changed=None, stack=None):
    graph = {s: parse_stack(root, s, cfg) for s in discover(root, env)}
    if stack:
        selected = {validate_stack(stack, root)}
    elif changed is None:
        selected = set(graph)
    else:
        selected = changed_stacks(graph, changed)
    ordered = levels(graph, selected)
    removed = sorted({"/".join(f.split("/")[:-1]) for f in (changed or []) if f.startswith(f"{LIVE}/{env}/")
                      and f.endswith("/terragrunt.hcl") and not (Path(root) / f).is_file()})
    return {"env": env, "levels": ordered, "deps": {s: [d for d in graph[s]["deps"] if d in selected] for s in selected},
            "removed": removed}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", required=True, choices=APPLY_ENVS)
    ap.add_argument("--base", help="last applied commit; none plans every stack of the environment")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--stack", help="one stack (workflow_dispatch)")
    ap.add_argument("--root", default=str(ROOT))
    ns = ap.parse_args(argv)
    try:
        if ns.stack and not ns.stack.startswith(f"{LIVE}/{ns.env}/"):
            raise StackError(f"{ns.stack} is not in {ns.env}")
        changed = None if ns.stack or not ns.base or ns.base == "none" else git_changed(ns.root, ns.base, ns.head)
        print(json.dumps(build(ns.root, ns.env, load_cfg(ns.root), changed, ns.stack)))
    except (StackError, subprocess.CalledProcessError) as e:
        print(f"stacks: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
