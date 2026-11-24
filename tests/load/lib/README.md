# lib

Pure modules (`profiles.js`, `options.js`, `requests.js`) have no k6 imports and are unit-tested with node; `run.js` is the only k6-bound file.
Load model and SLOs come from sections 1 and 8 of the architecture document.
`edge.js` (paths, headers, class by path, mix with lists), `traffic.js` (hot share, phases) and `stage-guard.js` are pure; `edge-run.js` is k6-bound and serves `tests/chaos/hot-merchant.js` and `scenarios/shedding.js`.
