# vendor

Third-party (upstream) code, unchanged and read-only. Sources, pinned commits and build flags are in [UPSTREAM.md](UPSTREAM.md).

| Directory | Origin | License | License file |
|---|---|---|---|
| `hyperswitch/` | juspay/hyperswitch | Apache-2.0 | `hyperswitch/LICENSE`, `hyperswitch/NOTICE` |
| `card-vault/` | juspay/hyperswitch-card-vault | Apache-2.0 | `card-vault/LICENSE` |
| `hyperswitch-e2e/` | juspay/hyperswitch, `cypress-tests/` | no license file in the directory; `package.json` says ISC, the rest of the repository is Apache-2.0 | taken from `hyperswitch/LICENSE` |

The project's own code (everything outside `vendor/`) is licensed under Apache-2.0, see the root `LICENSE`.
