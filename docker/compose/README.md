# compose

Commit-stage stack: router, drainer, scheduler and locker from their built images, Postgres, Redis, the vendored migrations (`migrate.sh`, idempotent, `--dry-run`) and `tests/load/mock-psp`.

```sh
python3 tools/ci/compose/compose_env.py --digests digests.json --registry <registry>/<prefix> --keys >docker/compose/.env
docker compose -f docker/compose/compose.yaml up -d --wait router drainer scheduler locker mock-psp
INTEGRATION_API_URL=http://127.0.0.1:8080 INTEGRATION_ADMIN_API_KEY=... python3 tests/integration/run.py
docker compose -f docker/compose/compose.yaml down -v
```

Ports are bound to 127.0.0.1 only; the passwords are local trust-auth placeholders, the admin and master keys are generated per run.
