---
name: mcp-env
description: Add an MCP server or environment: sanitization level, read role, synthetic PAN test.
---

# mcp-env

- Add the server to `.mcp.json` with only `${ENV_VAR}` references; define the environment in `.claude/mcp/<env>.yaml` (servers, sanitization level, role).
- Role `claude-agent-read-<env>` is ReadOnlyAccess without `secretsmanager:GetSecretValue`, `kms:Decrypt` or CDE account access.
- Sanitization level: dev `basic`, stage `standard`, prod `strict`; production never below `strict`.
- Test: a corpus of synthetic PAN, tokens and emails from `tests/sanitization/` must not appear in any gateway response.
