# mock-psp

Dummy PSP for load and chaos runs: `PORT=8089 node server.mjs`; endpoints `/authorize`, `/refund`, `/status`.
Env: `PSP_LATENCY_MIN_MS` (300), `PSP_LATENCY_MAX_MS` (1500), `PSP_ERROR_RATE`, `PSP_ERROR_STATUS` (503), `PSP_TIMEOUT_RATE`, `PSP_TIMEOUT_MS` (20000).
A timeout holds the connection and then drops it, which drives the router to the unknown state.
`POST /admin/config` changes the values at run time (for the PSP timeout experiment); `GET /admin/stats` counts outcomes.
Every response carries `X-Psp-Latency-Ms`, which the k6 scripts subtract to get the platform overhead.
