# capacity

`pod-capacity.yaml` holds RPS (or rows, tasks) per pod for router, locker, drainer and scheduler; `confirmed_per_pod` is filled from the breakpoint run, until then the baseline applies.
`forecast.yaml` holds the TPS of section 1; `capacity.py calc [--mode in-use|baseline|target]` prints min and max replicas per cell: min from the daily peak (at least 3), max = sale need x 1.5, pods = load / (capacity x 0.7), rounded up.
`capacity.py regression <previous-pod-capacity.yaml>` exits 1 when a confirmed capacity falls by more than 15%.
The document rounds some values down (locker 5/24, router baseline 79/357 from 3,300 RPS instead of 480 x 7 and 10,000 instead of 1,430 x 7), so the calculator can be up to two pods higher.
`miniyaml.py` reads these files without PyYAML.
