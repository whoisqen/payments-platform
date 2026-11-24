# tests

Offline checks with `node --test` (no k6): profile and weight maths, thresholds against the SLOs, request builders, mock PSP model and server.
Run from `tests/load`: `npm test`.
`edge.test.mjs` covers class by path, the stage guard refusal, hot share and shedding phases.
