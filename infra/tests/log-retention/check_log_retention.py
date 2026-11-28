#!/usr/bin/env python3
# Fail when a CloudWatch log group has no retention, a Lambda function has no log group of its own, or a log bucket never expires.
import re
import sys
from pathlib import Path

INFRA = Path(__file__).resolve().parents[2]
SKIP = {".terraform", "tests"}
HEADER = re.compile(r'^resource\s+"([a-z0-9_]+)"\s+"([A-Za-z0-9_-]+)"\s*\{', re.M)


def blocks(text):
    for m in HEADER.finditer(text):
        depth, i = 0, m.end() - 1
        while i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            if depth == 0:
                break
            i += 1
        yield m.group(1), m.group(2), text[m.end():i]


def check_module(name, text):
    errors = []
    found = list(blocks(text))
    for kind, label, body in found:
        if kind == "aws_cloudwatch_log_group":
            m = re.search(r"^\s*retention_in_days\s*=\s*(\S+)", body, re.M)
            if not m:
                errors.append(f"{name}: aws_cloudwatch_log_group.{label} has no retention_in_days")
            elif m.group(1) == "0":
                errors.append(f"{name}: aws_cloudwatch_log_group.{label} keeps logs forever (retention_in_days = 0)")
    lambda_groups = [b for k, _, b in found if k == "aws_cloudwatch_log_group" and "/aws/lambda/" in b]
    for kind, label, body in found:
        if kind == "aws_lambda_function" and not lambda_groups and "logging_config" not in body:
            errors.append(f"{name}: aws_lambda_function.{label} has no log group with a retention; Lambda would create one that never expires")
    for kind, label, body in found:
        if kind == "aws_s3_bucket" and "log" in label.lower():
            ref = re.compile(rf"aws_s3_bucket\.{re.escape(label)}(\[[^\]]*\])?\.")
            ok = any(k == "aws_s3_bucket_lifecycle_configuration" and ref.search(b) and re.search(r"expiration\s*\{[^}]*\bdays\s*=", b, re.S) for k, _, b in found)
            if not ok:
                errors.append(f"{name}: log bucket aws_s3_bucket.{label} has no lifecycle expiration")
    return errors


def modules(root):
    roots = {}
    for tf in sorted(root.rglob("*.tf")):
        if SKIP & set(tf.relative_to(root).parts):
            continue
        roots.setdefault(tf.parent, []).append(tf.read_text())
    return {d.relative_to(root).as_posix(): "\n".join(t) for d, t in roots.items()}


def main():
    errors = [e for name, text in modules(INFRA).items() for e in check_module(name, text)]
    for e in errors:
        print(f"log-retention: error: {e}")
    print(f"log-retention: {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
