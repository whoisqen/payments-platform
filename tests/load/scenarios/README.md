# scenarios

One file per profile; each only binds a profile name from `lib/profiles.js` to `options` and the iteration.
smoke 1 TPS, average 160 TPS (1,100 RPS), daily-peak 480 TPS (3,300), sale-peak 1,430 TPS (10,000), stress to 2,860 TPS (20,000), breakpoint (`abortOnFail`, one pod without HPA).
Stress asserts the SLOs only while the planned rate is at most 10,000 RPS; above it only 5xx below 0.1% (429 is allowed).
`platform_overhead_ms` assumes the dummy connector reports its own latency in the `X-Psp-Latency-Ms` response header.
