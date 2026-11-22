# chaos-mesh

Chaos Mesh manifests for the stage cluster only: `psp-timeout` (NetworkChaos 20 s delay to the mock PSP), `drainer-stall` (PodChaos), `dns-failure` (DNSChaos).
Hypothesis and stop condition are annotations; Chaos Mesh cannot watch alarms, so the pipeline deletes the object when the `chaos-stop` alarm fires.
DNSChaos needs the chaos-dns-server component installed; the target PSP is the mock in `tests/load/mock-psp`, never a real one.
Applying them is a pipeline job; none runs during a freeze or an open incident (`../lib/guard.py`).
