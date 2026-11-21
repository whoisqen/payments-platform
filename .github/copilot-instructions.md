# Review instructions

- Flag card data (PAN, CVV) in code, logs, traces, metric labels and fixtures; Rust card fields must use `Secret<T>`.
- A charge is never retried automatically; a PSP timeout leads to the unknown state and `sync`.
- Migrations are expand-contract only.
- Use the terms of `docs/glossary.md`.
- Do not review `vendor/` for style.
