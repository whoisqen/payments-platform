---
description: Recalculate min/max replicas from pod-capacity.yaml and the payment forecast.
---

# /capacity

1. Read `docs/capacity/pod-capacity.yaml`; replicas = ceil(load / (pod capacity x 0.7)); min is the daily peak but not less than 3; max is the sale-day need x 1.5.
2. Run `scripts/capacity/recalc.py --dry-run` and show the proposed values diff; open a PR, never change prod directly.
