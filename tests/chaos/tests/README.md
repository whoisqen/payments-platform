# tests

`test_chaos.py` covers the FIS validator, the guard, the region-switch runner (critical path against the RTO, abort before and after the point of no return) and the Chaos Mesh manifests (needs PyYAML, skipped otherwise).
Run from `tests/chaos`: `python3 -m unittest discover -s tests`.
The guard CLI exit codes and its agreement with the JS stage guard are covered too.
