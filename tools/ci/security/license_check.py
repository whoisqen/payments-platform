#!/usr/bin/env python3
# License inventory (syft CycloneDX plus cargo metadata) against policy/security/deps/licenses.toml; only a denied license exits 1.
import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

ALLOW, REVIEW, DENY, UNKNOWN = "allow", "review", "deny", "unknown"
RANK = {ALLOW: 0, REVIEW: 1, UNKNOWN: 1, DENY: 2}
TOKEN = re.compile(r"\(|\)|[^\s()]+")


class Policy:
    def __init__(self, allow, deny):
        self.allow = {x.lower() for x in allow}
        self.deny = {x.lower() for x in deny}

    @classmethod
    def load(cls, path):
        with open(path, "rb") as f:
            conf = tomllib.load(f)
        return cls(conf.get("allow", []), conf.get("deny", []) + conf.get("deny_aliases", []))

    def leaf(self, lic, exception=None):
        if exception and f"{lic} WITH {exception}".lower() in self.allow:
            return ALLOW
        if lic.lower() in self.deny:
            return DENY
        return ALLOW if lic.lower() in self.allow else REVIEW


def tokenize(expr):
    # cargo still accepts the legacy "MIT/Apache-2.0" form, which means OR
    return TOKEN.findall(expr.replace("/", " OR "))


def evaluate(expr, policy):
    # OR takes the best alternative, AND the worst part
    tokens = tokenize(expr or "")
    if not tokens:
        return UNKNOWN
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def take():
        nonlocal pos
        pos += 1
        return tokens[pos - 1]

    def primary():
        tok = take() if peek() is not None else None
        if tok is None or tok.upper() in ("AND", "OR", "WITH", ")"):
            raise ValueError(expr)
        if tok == "(":
            value = disjunction()
            if peek() != ")":
                raise ValueError(expr)
            take()
            return value
        if peek() is not None and peek().upper() == "WITH":
            take()
            exc = take() if peek() is not None else None
            if exc is None or exc in ("(", ")"):
                raise ValueError(expr)
            return policy.leaf(tok, exc)
        return policy.leaf(tok)

    def conjunction():
        parts = [primary()]
        while peek() is not None and peek().upper() == "AND":
            take()
            parts.append(primary())
        return max(parts, key=RANK.get)

    def disjunction():
        parts = [conjunction()]
        while peek() is not None and peek().upper() == "OR":
            take()
            parts.append(conjunction())
        return min(parts, key=RANK.get)

    try:
        value = disjunction()
    except (ValueError, IndexError):
        return UNKNOWN
    return value if pos == len(tokens) else UNKNOWN


def from_cyclonedx(doc):
    for c in doc.get("components", []) or []:
        exprs = []
        for entry in c.get("licenses", []) or []:
            if "expression" in entry:
                exprs.append(entry["expression"])
            else:
                lic = entry.get("license", {})
                exprs.append(lic.get("id") or lic.get("name") or "")
        exprs = [e for e in exprs if e]
        # syft lists every license it found for a package; any one of them is a valid grant
        expr = " OR ".join(f"({e})" for e in exprs) if exprs else ""
        yield f"{c.get('name', '?')}@{c.get('version', '?')}", expr


def from_cargo_metadata(doc):
    for p in doc.get("packages", []) or []:
        if p.get("source") is None:
            continue  # workspace and path crates of the upstream code itself
        yield f"{p['name']}@{p['version']}", p.get("license") or ""


def check(policy, packages):
    result = {ALLOW: [], REVIEW: [], DENY: [], UNKNOWN: []}
    seen = set()
    for name, expr in packages:
        if (name, expr) in seen:
            continue
        seen.add((name, expr))
        result[evaluate(expr, policy) if expr else UNKNOWN].append((name, expr))
    return result


def summary(result):
    lines = [
        "### License inventory",
        "",
        f"allowed {len(result[ALLOW])}, review {len(result[REVIEW])}, no license {len(result[UNKNOWN])}, denied {len(result[DENY])}",
    ]
    for title, key in (("Denied (blocking)", DENY), ("Review (not blocking)", REVIEW)):
        if result[key]:
            lines += ["", f"#### {title}", ""] + [f"- `{n}`: {e}" for n, e in sorted(result[key])]
    return "\n".join(lines) + "\n"


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--policy", required=True)
    p.add_argument("--cyclonedx", action="append", default=[])
    p.add_argument("--cargo-metadata", action="append", default=[])
    p.add_argument("--summary")
    a = p.parse_args(argv)
    policy = Policy.load(a.policy)
    packages = []
    for f in a.cyclonedx:
        packages += list(from_cyclonedx(json.loads(Path(f).read_text())))
    for f in a.cargo_metadata:
        packages += list(from_cargo_metadata(json.loads(Path(f).read_text())))
    result = check(policy, packages)
    text = summary(result)
    print(text, end="")
    if a.summary:
        with open(a.summary, "a") as f:
            f.write(text)
    for name, expr in result[DENY]:
        print(f"::error::{name} is licensed {expr}, which is on the deny list")
    return 1 if result[DENY] else 0


if __name__ == "__main__":
    sys.exit(main())
