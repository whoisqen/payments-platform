#!/usr/bin/env python3
"""Write Grafana dashboard JSON into observability/dashboards/<level>/<uid>.json."""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dashboards  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "dashboards"


def render():
    return {f"{level}/{d.uid}.json": json.dumps(d.build(), indent=2, sort_keys=False) + "\n" for level, d in dashboards.build_all()}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    stale = []
    for rel, text in render().items():
        target = OUT / rel
        if args.check:
            if not target.exists() or target.read_text() != text:
                stale.append(rel)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
    if stale:
        print("stale dashboards: " + ", ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
