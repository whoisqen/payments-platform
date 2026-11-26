#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).resolve().parent / "image-paths.yaml"
AREAS = Path(__file__).resolve().parent / "areas.yaml"
SERVICES = ["router", "drainer", "scheduler", "locker", "control-center", "vault-snapshot", "smoke"]
UNCLAIMED_ROOTS = ("docker/", "vendor/")


def parse_paths(text):
    # a restricted YAML subset keeps the changes job free of a PyYAML install
    data, top, sub = {}, None, None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip() if not raw.lstrip().startswith("- ") else raw.rstrip()
        if not line.strip():
            continue
        item = re.match(r"^\s+- (\S+)\s*(#.*)?$", line)
        if item:
            target = data[top][sub] if sub else data[top]
            target.append(item.group(1))
        elif re.match(r"^\S[^:]*:$", line):
            top, sub = line[:-1], None
            data[top] = []
        elif re.match(r"^  \S[^:]*:$", line):
            sub = line.strip()[:-1]
            if not isinstance(data[top], dict):
                data[top] = {}
            data[top][sub] = []
        else:
            raise ValueError(f"unsupported line: {raw!r}")
    return data


def matches(path, entry):
    return path.startswith(entry) if entry.endswith("/") else path == entry


def any_match(path, entries):
    return any(matches(path, e) for e in entries)


def images_for(files, cfg):
    rebuild_all = cfg["rebuild_all"]
    images = cfg["images"]
    selected, everything = set(), False
    for f in files:
        if f.endswith("README.md") or any_match(f, cfg.get("not_image_inputs", [])):
            continue
        if any_match(f, rebuild_all):
            everything = True
        hit = [name for name, entries in images.items() if any_match(f, entries)]
        selected.update(hit)
        if not hit and f.startswith(UNCLAIMED_ROOTS) and not any_match(f, rebuild_all):
            everything = True
    if everything:
        return list(SERVICES), True
    return [s for s in SERVICES if s in selected], False


def mise_rust_lines_changed(diff_text, tools):
    keys = "|".join(re.escape(t) for t in tools)
    key = re.compile(rf'^[+-]\s*"?({keys})"?\s*=')
    return any(key.match(x) for x in diff_text.splitlines() if not x.startswith(("+++", "---")))


def areas_for(files, cfg, labels=(), mise_rust=False):
    names = list(cfg["areas"])
    rust = set(cfg["rust_areas"])
    common = cfg["common"]
    if set(labels) & set(cfg["full_labels"]):
        return {n: True for n in names}, True
    areas = {n: any(any_match(f, entries) for f in files) for n, entries in cfg["areas"].items()}
    if any(any_match(f, common["python_only"]) for f in files):
        areas["python"] = True
    if any(any_match(f, common["all_but_rust"]) for f in files):
        areas.update({n: True for n in names if n not in rust})
    rust_all = mise_rust or any(any_match(f, common["rust"]) for f in files)
    if rust_all:
        areas.update({n: True for n in rust})
    return areas, rust_all


def mode_areas(cfg, mode):
    rust = set(cfg["rust_areas"])
    if mode == "full":
        return {n: n not in rust for n in cfg["areas"]}, False
    if mode == "rust":
        return {n: n in rust for n in cfg["areas"]}, True
    return {n: True for n in cfg["areas"]}, True


def git(*args):
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else None


def changed_files(base, head):
    out = git("diff", "--name-only", f"{base}...{head}")
    return None if out is None else [x for x in out.splitlines() if x]


def mise_rust_changed(base, head, tools):
    out = git("diff", "-U0", f"{base}...{head}", "--", "mise.toml")
    # an unreadable diff selects Rust: an extra run is cheaper than a skipped one
    return True if out is None else mise_rust_lines_changed(out, tools)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--files-from", help="read paths from this file, - for stdin")
    ap.add_argument("--mise-diff", help="with --files-from: a diff of mise.toml to read instead of git")
    ap.add_argument("--labels", default="", help="comma-separated pull request labels")
    ap.add_argument("--mode", choices=["diff", "full", "rust"], default="diff",
                    help="full: every area but Rust (daily); rust: only the Rust areas, every crate (weekly)")
    ap.add_argument("--paths", metavar="SERVICE", help="print the input paths of one image and exit")
    ns = ap.parse_args(argv)
    cfg = parse_paths(CONFIG.read_text(encoding="utf-8"))
    if ns.paths:
        print("\n".join(cfg["images"][ns.paths] + cfg["rebuild_all"]))
        return 0
    acfg = parse_paths(AREAS.read_text(encoding="utf-8"))
    tools = acfg["common"]["rust_mise_tools"]
    labels = [x.strip() for x in ns.labels.split(",") if x.strip()]
    mise_rust = False
    if ns.files_from:
        src = sys.stdin if ns.files_from == "-" else open(ns.files_from, encoding="utf-8")
        files = [x.strip() for x in src.read().splitlines() if x.strip()]
        if ns.mise_diff:
            mise_rust = mise_rust_lines_changed(Path(ns.mise_diff).read_text(encoding="utf-8"), tools)
    else:
        files = changed_files(ns.base, ns.head) if ns.base and ns.head else None
        if files and "mise.toml" in files:
            mise_rust = mise_rust_changed(ns.base, ns.head, tools)
    # an unknown diff must build and test everything: an extra run is cheaper than a skipped one
    unknown = files is None
    files = files or []
    images, everything = images_for(files, cfg) if not unknown else (list(SERVICES), True)
    if ns.mode != "diff" or unknown:
        areas, rust_all = mode_areas(acfg, "all" if ns.mode == "diff" else ns.mode)
    else:
        areas, rust_all = areas_for(files, acfg, labels, mise_rust)
    result = {"images": images, "all": everything, "rust_all": rust_all, **{f"area_{k}": v for k, v in areas.items()}}
    lines = [f"images={json.dumps(images)}", f"any_image={'true' if images else 'false'}"]
    lines += [f"{k}={str(v).lower()}" for k, v in result.items() if k == "rust_all" or k.startswith("area_")]
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    print(json.dumps(result))
    return 0

if __name__ == "__main__":
    sys.exit(main())
