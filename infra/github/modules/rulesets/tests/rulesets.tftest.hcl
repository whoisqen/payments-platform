mock_provider "github" {}

variables {
  repository      = "payments-platform"
  required_checks = ["ci-gate", "spec-gate"]
  approvals       = 2
  tag_bypass = {
    actor_id   = 1
    actor_type = "Integration"
  }
  merge_queue = true
}

run "main" {
  command = plan

  assert {
    condition     = github_repository_ruleset.main.rules[0].required_linear_history && github_repository_ruleset.main.rules[0].required_signatures && github_repository_ruleset.main.rules[0].non_fast_forward
    error_message = "linear history, signed commits and no force push"
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].required_approving_review_count == 2 && github_repository_ruleset.main.rules[0].pull_request[0].require_code_owner_review
    error_message = "2 approvals, one from CODEOWNERS"
  }
  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].dismiss_stale_reviews_on_push && github_repository_ruleset.main.rules[0].pull_request[0].require_last_push_approval
    error_message = "stale reviews are dismissed and the last push needs approval"
  }
  assert {
    condition     = length(github_repository_ruleset.main.rules[0].required_status_checks[0].required_check) == 2 && length(github_repository_ruleset.main.rules[0].merge_queue) == 1
    error_message = "ci-gate and spec-gate are required and the merge queue is on"
  }
}

run "version_tags" {
  command = plan

  assert {
    condition     = github_repository_ruleset.version_tags.target == "tag" && contains(github_repository_ruleset.version_tags.conditions[0].ref_name[0].include, "refs/tags/v*")
    error_message = "the tag rule targets v*"
  }
  assert {
    condition     = github_repository_ruleset.version_tags.rules[0].creation && github_repository_ruleset.version_tags.rules[0].deletion && github_repository_ruleset.version_tags.rules[0].update
    error_message = "creation, update and deletion are restricted"
  }
  assert {
    condition     = github_repository_ruleset.version_tags.bypass_actors[0].actor_type == "Integration"
    error_message = "only the tagging app bypasses"
  }
}
