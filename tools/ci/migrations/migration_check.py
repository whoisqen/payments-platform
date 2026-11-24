#!/usr/bin/env python3
"""Checks the Diesel migrations a pull request adds or changes.

  migration_check.py check --base B --head H [--contract]    structure and expand-contract rules, exit 1 on an error
  migration_check.py list --base B --head H --scope SCOPE    paths for the next step: squawk-tx, squawk-notx, new (directory names per root)
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# a platform-owned migrations directory is added here
ROOTS = ("vendor/hyperswitch/migrations", "vendor/card-vault/migrations")
CHART = "deploy/charts/migrations"
NAME = re.compile(r"^(\d{4}-\d{2}-\d{2}-\d{6})_[A-Za-z0-9_-]+$")
INITIAL = re.compile(r"^(0{14})_diesel_initial_setup$")
DESTRUCTIVE = [
    (r"\bDROP\s+(TABLE|COLUMN|TYPE|SCHEMA)\b", "drop"),
    (r"\bTRUNCATE\b", "truncate"),
    (r"\bRENAME\b", "rename"),
    (r"\bSET\s+NOT\s+NULL\b", "set not null"),
    (r"\bALTER\s+COLUMN\s+\S+\s+(SET\s+DATA\s+)?TYPE\b", "alter column type"),
]
SCHEMA_ADD = re.compile(r"\bCREATE\s+(OR\s+REPLACE\s+)?(UNIQUE\s+)?(TABLE|INDEX|TYPE|SEQUENCE|VIEW|FUNCTION|TRIGGER)\b|\bADD\b", re.I)
NO_TX = re.compile(r"^\s*run_in_transaction\s*=\s*false\s*(#.*)?$", re.M)


def strip_sql(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"--[^\n]*", " ", text)


def destructive_hits(sql):
    clean = strip_sql(sql)
    return sorted({label for pat, label in DESTRUCTIVE if re.search(pat, clean, re.I)})


def adds_schema(sql):
    # the destructive statements themselves are removed first so a RENAME alone is not "mixed"
    clean = strip_sql(sql)
    return bool(SCHEMA_ADD.search(clean))


def stamp(name):
    m = NAME.match(name) or INITIAL.match(name)
    return m.group(1) if m else None


def snapshot_guard(values, job):
    errors = []
    block = re.search(r"^snapshot:\s*\n((?:[ \t]+.*\n|\n)*)", values + "\n", re.M)
    body = block.group(1) if block else ""
    if not re.search(r"^\s+enabled:\s*true\b", body, re.M):
        errors.append(f"{CHART}/values.yaml: snapshot.enabled must be true")
    if not re.search(r"^\s+retentionDays:\s*35\b", body, re.M):
        errors.append(f"{CHART}/values.yaml: snapshot.retentionDays must be 35")
    first = re.search(r"initContainers:\s*\n\s*-\s*name:\s*(\S+)", job)
    if not first or first.group(1) != "pre-migration-snapshot":
        got = first.group(1) if first else "none"
        errors.append(f"{CHART}/templates/job.yaml: first init container is {got}, policy require-migration-snapshot needs pre-migration-snapshot")
    if "SNAPSHOT_RETENTION_DAYS" not in job:
        errors.append(f"{CHART}/templates/job.yaml: SNAPSHOT_RETENTION_DAYS is not set")
    return errors


def split_path(path):
    for root in ROOTS:
        if path.startswith(root + "/"):
            parts = path[len(root) + 1:].split("/", 1)
            return root, parts[0], parts[1] if len(parts) > 1 else ""
    return None


def group_changes(changes):
    # {(root, dir): {status: [files]}}
    out = {}
    for status, path in changes:
        sp = split_path(path)
        if sp and sp[2]:
            out.setdefault((sp[0], sp[1]), {}).setdefault(status[0], []).append(sp[2])
    return out


def check(existing, changes, read, exists, contract=False, guard=None):
    """existing: {root: set of directory names on the base}; read/exists work on the head tree."""
    errors, warnings = [], []
    grouped = group_changes(changes)
    seen = {r: {stamp(n): n for n in names if stamp(n)} for r, names in existing.items()}
    for (root, d), by in sorted(grouped.items()):
        where = f"{root}/{d}"
        if d in existing.get(root, set()):
            if "D" in by or "M" in by:
                warnings.append(f"{where}: an existing migration is {'deleted' if 'D' in by else 'modified'}; applied databases do not re-run it")
            continue
        ts = stamp(d)
        if ts is None:
            errors.append(f"{where}: name must be YYYY-MM-DD-HHMMSS_name")
            continue
        for f in ("up.sql", "down.sql"):
            if not exists(f"{where}/{f}"):
                errors.append(f"{where}: {f} is missing")
        if ts in seen.get(root, {}):
            errors.append(f"{where}: timestamp {ts} is already used by {seen[root][ts]}; one directory per timestamp")
        newest = max(seen.get(root, {"": ""}))
        if ts < newest and ts not in seen.get(root, {}):
            errors.append(f"{where}: older than the newest migration on the base ({newest}); rebase and rename to avoid multiple heads")
        seen.setdefault(root, {})[ts] = d
        if not exists(f"{where}/up.sql"):
            continue
        up = read(f"{where}/up.sql")
        no_tx = exists(f"{where}/metadata.toml") and bool(NO_TX.search(read(f"{where}/metadata.toml")))
        if re.search(r"\bCONCURRENTLY\b", strip_sql(up), re.I) and not no_tx:
            errors.append(f"{where}: CONCURRENTLY needs metadata.toml with run_in_transaction = false (Diesel wraps the migration in a transaction)")
        if no_tx and not re.search(r"\bCONCURRENTLY\b", strip_sql(up), re.I):
            warnings.append(f"{where}: run_in_transaction = false without CONCURRENTLY; the exception is only for concurrent index builds")
        hits = destructive_hits(up)
        if not hits:
            continue
        if adds_schema(re.sub("|".join(p for p, _ in DESTRUCTIVE), " ", strip_sql(up), flags=re.I)):
            errors.append(f"{where}: destructive statements ({', '.join(hits)}) share a migration with schema additions; split expand and contract")
        if not contract:
            errors.append(f"{where}: destructive ({', '.join(hits)}) needs the contract-migration label")
        elif guard is not None:
            errors += [f"{where}: {e}" for e in guard()]
    return errors, warnings


def git(*args):
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def load(base, head):
    raw = git("diff", "--name-status", "--no-renames", f"{base}...{head}", "--", *ROOTS)
    changes = [tuple(line.split("\t", 1)) for line in raw.splitlines() if "\t" in line]
    existing = {}
    for r in ROOTS:
        listing = git("ls-tree", "--name-only", base, r + "/").splitlines()
        existing[r] = {p.rsplit("/", 1)[1] for p in listing}
    return existing, changes


def new_dirs(existing, changes):
    return sorted((r, d) for (r, d), by in group_changes(changes).items() if d not in existing.get(r, set()) and "A" in by)


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check", "list"):
        p = sub.add_parser(name)
        p.add_argument("--base", required=True)
        p.add_argument("--head", required=True)
    sub.choices["check"].add_argument("--contract", action="store_true", help="the PR carries the contract-migration label")
    sub.choices["list"].add_argument("--scope", required=True, choices=["squawk-tx", "squawk-notx", "new"])
    sub.choices["list"].add_argument("--root", help="restrict to one migrations root")
    ns = ap.parse_args(argv)
    existing, changes = load(ns.base, ns.head)

    def read(p):
        return (ROOT / p).read_text(encoding="utf-8")

    def exists(p):
        return (ROOT / p).is_file()

    if ns.cmd == "list":
        if ns.scope == "new":
            for r, d in new_dirs(existing, changes):
                if not ns.root or ns.root == r:
                    print(f"{r} {d}")
            return 0
        for (r, d), by in sorted(group_changes(changes).items()):
            up = f"{r}/{d}/up.sql"
            if "up.sql" not in by.get("A", []) + by.get("M", []) or not exists(up):
                continue
            meta = f"{r}/{d}/metadata.toml"
            no_tx = exists(meta) and bool(NO_TX.search(read(meta)))
            if no_tx == (ns.scope == "squawk-notx"):
                print(up)
        return 0

    def guard():
        return snapshot_guard(read(f"{CHART}/values.yaml"), read(f"{CHART}/templates/job.yaml"))

    errors, warnings = check(existing, changes, read, exists, ns.contract, guard)
    for w in warnings:
        print(f"::warning::{w}")
    for e in errors:
        print(f"::error::{e}")
    print(f"migration_check: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
