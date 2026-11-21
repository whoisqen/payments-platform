mock_provider "github" {}

variables {
  name               = "payments-platform"
  description        = "test"
  visibility         = "private"
  allow_squash_merge = true
  allow_rebase_merge = false
  allowed_actions    = ["actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"]
}

run "settings" {
  command = plan

  assert {
    condition     = github_repository.this.visibility == "private" && github_repository.this.allow_squash_merge && !github_repository.this.allow_merge_commit && github_repository.this.delete_branch_on_merge
    error_message = "private, squash merge only, branches deleted on merge"
  }
  assert {
    condition     = github_repository_vulnerability_alerts.this.enabled
    error_message = "vulnerability alerts are on"
  }
  assert {
    condition     = github_workflow_repository_permissions.this.default_workflow_permissions == "read"
    error_message = "GITHUB_TOKEN is read-only"
  }
  assert {
    condition     = github_actions_repository_permissions.this.allowed_actions == "selected" && alltrue([for p in var.allowed_actions : can(regex("@[0-9a-f]{40}$", p))])
    error_message = "actions are allowlisted and pinned by SHA"
  }
}
