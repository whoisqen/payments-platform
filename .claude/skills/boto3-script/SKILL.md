---
name: boto3-script
description: Write an idempotent operations script with dry-run, retries and structured logs.
---

# boto3-script

- Idempotent; check current state before any change; `--dry-run` is the default behaviour for destructive operations.
- Retry with exponential backoff and full jitter; structured logs; one script is one atomic operation; typed Python.
- Bash scripts use `set -euo pipefail` and pass shellcheck.
