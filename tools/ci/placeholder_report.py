#!/usr/bin/env python3
"""Report of REPLACE_ placeholders under deploy/ and infra/live, with the source of each value.

  placeholder_report.py                 every placeholder, warnings only, exit code 0
  placeholder_report.py --env stage     only deploy/envs/stage and infra/live/stage: what blocks the apply of that environment
  placeholder_report.py --env stage --strict   the same, but exit code 1 when any remains

Chart defaults under deploy/charts are the contract of a chart (the schema accepts the token) and are reported only without --env.
A value that comes from an `infra/live` output is wired in after that stack is applied; the others are known only to the owner.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN = ("deploy", "infra/live")
PLACEHOLDER = re.compile(r"REPLACE_\w+")
# token -> (where the value comes from, who supplies it)
SOURCES = {
    "REPLACE_LOCKER_POD_SG_ID": ("output locker_pod_security_group_id of the eks stack of the cluster that runs the locker", "pipeline, after the eks stack is applied"),
}
OWNER = ("not in infra/live outputs", "owner")


def in_env(path, env):
    return path.startswith((f"deploy/envs/{env}/", f"infra/live/{env}/"))


def scan(root, dirs=SCAN, env=None):
    found = []
    for d in dirs:
        base = root / d
        if not base.is_dir():
            continue
        for path in sorted(p for p in base.rglob("*") if p.is_file()):
            rel = path.relative_to(root).as_posix()
            if env and not in_env(rel, env):
                continue
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except (UnicodeDecodeError, OSError):
                continue
            for n, line in enumerate(lines, 1):
                for m in PLACEHOLDER.finditer(line):
                    found.append((rel, n, m.group(0)))
    return found


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    strict = "--strict" in args
    env = None
    if "--env" in args:
        i = args.index("--env")
        env = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if a != "--strict"]
    root = Path(args[0]) if args else ROOT
    found = scan(root, env=env)
    for f, n, token in found:
        source, owner = SOURCES.get(token, OWNER)
        print(f"::warning file={f},line={n}::placeholder {token} ({source}; supplied by {owner})")
    scope = f"for {env}" if env else f"in {', '.join(SCAN)}"
    print(f"{len(found)} REPLACE_ placeholders {scope} ({'blocking' if strict else 'warning only'})")
    return 1 if strict and found else 0


if __name__ == "__main__":
    sys.exit(main())
