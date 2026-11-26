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


def areas_for(files, cfg):
    return {name: any(any_match(f, entries) for f in files) for name, entries in cfg["areas"].items()}


def changed_files(base, head):
    out = subprocess.run(["git", "diff", "--name-only", f"{base}...{head}"], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return [x for x in out.stdout.splitlines() if x]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--files-from", help="read paths from this file, - for stdin")
    ap.add_argument("--paths", metavar="SERVICE", help="print the input paths of one image and exit")
    ns = ap.parse_args(argv)
    cfg = parse_paths(CONFIG.read_text(encoding="utf-8"))
    if ns.paths:
        print("\n".join(cfg["images"][ns.paths] + cfg["rebuild_all"]))
        return 0
    if ns.files_from:
        src = sys.stdin if ns.files_from == "-" else open(ns.files_from, encoding="utf-8")
        files = [x.strip() for x in src.read().splitlines() if x.strip()]
    else:
        files = changed_files(ns.base, ns.head) if ns.base and ns.head else None
    # an unknown diff must build everything: an extra build is cheaper than a skipped one
    unknown = files is None
    files = files or []
    images, everything = images_for(files, cfg) if not unknown else (list(SERVICES), True)
    areas = areas_for(files, cfg) if not unknown else {k: True for k in cfg["areas"]}
    result = {"images": images, "all": everything, **{f"area_{k}": v for k, v in areas.items()}}
    lines = [f"images={json.dumps(images)}", f"any_image={'true' if images else 'false'}"]
    lines += [f"{k}={str(v).lower()}" for k, v in result.items() if k.startswith("area_")]
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
