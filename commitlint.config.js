// Mirrors tools/lint/spec-gate: type, scope, 72 characters and a summary that starts in lower case.
const types = ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"];
const scopes = ["router", "drainer", "scheduler", "locker", "control-center", "infra", "deploy", "policy",
  "observability", "docker", "ci", "claude", "docs", "vendor", "specs"];

module.exports = {
  plugins: [
    {
      rules: {
        "summary-starts-lower": (parsed) => [
          !/^[A-Z]/.test(parsed.subject || ""),
          "the summary must start with a lower-case letter",
        ],
      },
    },
  ],
  rules: {
    "type-enum": [2, "always", types],
    "scope-enum": [2, "always", scopes],
    "scope-empty": [2, "never"],
    "header-max-length": [2, "always", 72],
    "subject-empty": [2, "never"],
    "summary-starts-lower": [2, "always"],
  },
};
