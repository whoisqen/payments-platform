#!/usr/bin/env python3
"""Warning-only report of REPLACE_ placeholders under deploy/ and infra/live; always exits 0."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN = ("deploy", "infra/live")
PLACEHOLDER = re.compile(r"REPLACE_\w+")


def scan(root, dirs=SCAN):
    found = []
    for d in dirs:
        base = root / d
        if not base.is_dir():
            continue
        for path in sorted(p for p in base.rglob("*") if p.is_file()):
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except (UnicodeDecodeError, OSError):
                continue
            for n, line in enumerate(lines, 1):
                for m in PLACEHOLDER.finditer(line):
                    found.append((path.relative_to(root).as_posix(), n, m.group(0)))
    return found


def main(argv=None):
    root = Path(argv[0]) if argv else ROOT
    found = scan(root)
    for f, n, token in found:
        print(f"::warning file={f},line={n}::placeholder {token}")
    print(f"{len(found)} REPLACE_ placeholders in {', '.join(SCAN)} (warning only)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
