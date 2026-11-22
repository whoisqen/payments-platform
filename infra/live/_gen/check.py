#!/usr/bin/env python3
"""Offline Terragrunt checks: sources, inputs against module variables, dependencies, outputs, cycles, layout."""
import hcl2, os, re, sys

LIVE = "/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-ae6ce5dd4f5691ab7/infra/live"
MODS = ["/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-ae6ce5dd4f5691ab7/infra/modules",
        "/data/vlad/portfolio/payments-platform/infra/modules"]
errors = []


def err(m):
    errors.append(m)


def q(s):
    return s.strip().strip('"') if isinstance(s, str) else s


def load(p):
    with open(p) as f:
        return hcl2.load(f)


def modpath(name):
    for m in MODS:
        if os.path.isdir(os.path.join(m, name)):
            return os.path.join(m, name)
    return None


_vars, _outs = {}, {}


def variables(mod):
    if mod not in _vars:
        d = load(os.path.join(modpath(mod), "variables.tf"))
        _vars[mod] = {q(list(v)[0]): ("default" in list(v.values())[0]) for v in d.get("variable", [])}
    return _vars[mod]


def outputs(mod):
    if mod not in _outs:
        txt = open(os.path.join(modpath(mod), "outputs.tf")).read()
        _outs[mod] = set(re.findall(r'^output "([\w-]+)"', txt, re.M))
    return _outs[mod]


root = load(os.path.join(LIVE, "terragrunt.hcl"))
root_inputs = {q(k) for k in root["inputs"] if k != "__is_block__"}

stacks = {}
for d, dirs, files in os.walk(LIVE):
    dirs[:] = [x for x in dirs if x != "_gen"]
    n = len([f for f in files if f != "README.md"])
    if n > 10:
        err(f"{d}: {n} files")
    for x in dirs + files:
        if x != x.lower() or "_" in x and not x.startswith("_") and not x.endswith(".hcl"):
            err(f"{d}/{x}: not lower-case kebab-case")
    if "terragrunt.hcl" in files and d != LIVE:
        stacks[d] = os.path.join(d, "terragrunt.hcl")

rel = lambda p: os.path.relpath(p, LIVE)
for p in stacks.values():
    parts = rel(p).split("/")
    if parts[0] in ("prod", "cde-prod"):
        err(f"{rel(p)}: forbidden env")

graph = {}
module_of = {}
for d, p in sorted(stacks.items()):
    txt = open(p).read()
    cfg = load(p)
    incs = {q(list(i)[0]): list(i.values())[0] for i in cfg["include"]}
    m = re.search(r"/_envcommon/([\w-]+/[\w-]+\.hcl)", q(incs["envcommon"]["path"]))
    ec_path = os.path.join(LIVE, "_envcommon", m.group(1))
    if not os.path.isfile(ec_path):
        err(f"{rel(p)}: envcommon {m.group(1)} missing")
        continue
    ec = load(ec_path)
    src = q(ec["terraform"][0]["source"])
    mm = re.search(r"\$\{get_repo_root\(\)\}/infra/modules//([\w-]+)$", src)
    if not mm or not modpath(mm.group(1)):
        err(f"{rel(ec_path)}: source {src} does not resolve")
        continue
    mod = mm.group(1)
    module_of[d] = mod
    inp = {q(k) for k in cfg.get("inputs", {}) if k != "__is_block__"} | {q(k) for k in ec["inputs"]}
    decl = variables(mod)
    for k in inp:
        if k not in decl:
            err(f"{rel(p)}: input {k} is not a variable of {mod}")
    for v, has_default in decl.items():
        if not has_default and v not in inp and v not in root_inputs:
            err(f"{rel(p)}: required variable {v} of {mod} is not provided")
    for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"]:
        if k not in {q(x) for x in ec["inputs"]["tags"]}:
            err(f"{rel(ec_path)}: tag {k} missing")
    # dependencies
    deps = {}
    for b in cfg.get("dependency", []):
        name = q(list(b)[0])
        body = list(b.values())[0]
        target = os.path.normpath(os.path.join(d, q(body["config_path"])))
        if target not in stacks:
            err(f"{rel(p)}: dependency {name} -> {rel(target)} does not exist")
            continue
        deps[name] = target
        if "mock_outputs" not in body or "mock_outputs_allowed_terraform_commands" not in body:
            err(f"{rel(p)}: dependency {name} lacks mock_outputs or allowed commands")
        deps[name] = (target, set(q(k) for k in body.get("mock_outputs", {}) if k != "__is_block__"))
    graph[d] = [t for t, _ in deps.values()]
    for name, out in set(re.findall(r"dependency\.(\w+)\.outputs\.(\w+)", txt)):
        if name not in deps:
            err(f"{rel(p)}: dependency.{name} not declared")
            continue
        target, mocks = deps[name]
        tm = module_of.get(target)
        if tm is None:
            # target not yet visited; resolve through its own envcommon later
            continue
        if out not in outputs(tm):
            err(f"{rel(p)}: dependency.{name}.outputs.{out} is not an output of {tm}")
        if out not in mocks:
            err(f"{rel(p)}: dependency {name} mock lacks {out}")
    for name in deps:
        if not re.search(rf"dependency\.{name}\.", txt):
            err(f"{rel(p)}: dependency {name} is unused")

# second pass for outputs of targets visited later
for d, p in sorted(stacks.items()):
    txt = open(p).read()
    cfg = load(p)
    for b in cfg.get("dependency", []):
        name = q(list(b)[0])
        target = os.path.normpath(os.path.join(d, q(list(b.values())[0]["config_path"])))
        tm = module_of.get(target)
        for n2, out in set(re.findall(r"dependency\.(\w+)\.outputs\.(\w+)", txt)):
            if n2 == name and tm and out not in outputs(tm):
                err(f"{rel(p)}: dependency.{name}.outputs.{out} is not an output of {tm}")

# cycles
state = {}


def visit(n, stack):
    if state.get(n) == 2:
        return
    if state.get(n) == 1:
        err("cycle: " + " -> ".join(rel(x) for x in stack + [n]))
        return
    state[n] = 1
    for t in graph.get(n, []):
        visit(t, stack + [n])
    state[n] = 2


for n in graph:
    visit(n, [])

print(f"{len(stacks)} stacks, {len(set(module_of.values()))} modules used")
for e in errors[:60]:
    print("ERROR", e)
print(len(errors), "error(s)")
sys.exit(1 if errors else 0)
