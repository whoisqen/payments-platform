#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIGEST = re.compile(r"@sha256:[a-f0-9]{64}$")


def logical_lines(text):
    buf, start = "", 0
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not buf and (not line or line.startswith("#")):
            continue
        if not buf:
            start = n
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        yield start, (buf + line).strip()
        buf = ""


def check(text):
    errors, stages, user = [], set(), None
    for n, line in logical_lines(text):
        word, _, rest = line.partition(" ")
        word = word.upper()
        if word == "FROM":
            parts = [p for p in rest.split() if not p.startswith("--")]
            image = parts[0]
            if len(parts) >= 3 and parts[1].upper() == "AS":
                stages.add(parts[2])
            if image in stages or image == "scratch":
                continue
            if not DIGEST.search(image):
                errors.append(f"{n}: FROM {image} is not pinned by digest")
            if re.search(r":latest(@|$)", image) or image.endswith(":latest"):
                errors.append(f"{n}: FROM uses the latest tag")
        elif word == "USER":
            user = rest.strip()
        elif word == "ADD" and re.search(r"https?://", rest):
            errors.append(f"{n}: ADD from a URL")
        elif word == "ENTRYPOINT" and not rest.strip().startswith("["):
            errors.append(f"{n}: ENTRYPOINT is not in exec form")
        elif word == "RUN" and re.search(r"(curl|wget)[^|]*\|\s*(ba)?sh", rest):
            errors.append(f"{n}: pipes a download into a shell")
    if user is None or not re.fullmatch(r"10001(:10001)?", user):
        errors.append(f"final USER is {user!r}, expected 10001:10001")
    return errors


def main(argv=None):
    paths = [Path(a) for a in (argv if argv is not None else sys.argv[1:])] or sorted((ROOT / "docker").glob("*/Dockerfile"))
    bad = 0
    for p in paths:
        for e in check(p.read_text(encoding="utf-8")):
            print(f"dockerfile-check: error: {p}:{e}")
            bad += 1
    print(f"dockerfile-check: {len(paths)} file(s), {bad} error(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
