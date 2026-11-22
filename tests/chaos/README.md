# tests/chaos

Chaos experiments as code, stage only; each has a hypothesis and a stop condition, none runs during a freeze or an open incident.

- `fis/`: AWS FIS templates (AZ loss, node loss, spot interruption, MemoryDB failover, Aurora writer failover, MSK broker loss).
- `chaos-mesh/`: PSP timeout, drainer stall, DNS failure.
- `region-switch/`: quarterly full-switch scenario of D7 (us-east-1, then us-east-2) and the plan-B variant, with a dry-run runner.
- `lib/`: guard (freeze, incident, environment) and the FIS template validator.
- Offline proof: `python3 -m unittest discover -s tests` from this directory. Catalog: `docs/chaos/catalog.md`.
