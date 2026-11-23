// Mirrors tools/lint/spec-gate: type, scope, 72 characters and a summary that starts in lower case.
const types = ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"];
const scopes = ["router", "drainer", "scheduler", "locker", "control-center", "infra", "deploy", "policy",
  "observability", "docker", "ci", "claude", "docs", "vendor", "specs"];

module.exports = {
  // The gate accepts `type(scope)!: summary`; the default parser does not know the breaking-change marker.
  parserPreset: {
    parserOpts: {
      headerPattern: /^(\w*)(?:\((.*)\))?!?: (.*)$/,
      headerCorrespondence: ["type", "scope", "subject"],
    },
  },
  plugins: [
    {
      rules: {
        "summary-starts-lower": (parsed) => [
          /^[a-z]/.test(parsed.subject || ""),
          "the summary must start with a lower-case letter (a-z)",
        ],
        "scope-single": (parsed) => [
          !/[,/\\]/.test(parsed.scope || ""),
          "exactly one scope is allowed",
        ],
      },
    },
  ],
  rules: {
    "scope-single": [2, "always"],
    "type-enum": [2, "always", types],
    "scope-enum": [2, "always", scopes],
    "scope-empty": [2, "never"],
    "header-max-length": [2, "always", 72],
    "subject-empty": [2, "never"],
    "summary-starts-lower": [2, "always"],
  },
};
