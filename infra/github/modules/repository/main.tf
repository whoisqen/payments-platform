resource "github_repository" "this" {
  name                   = var.name
  description            = var.description
  visibility             = var.visibility
  has_issues             = true
  has_projects           = true
  has_wiki               = false
  allow_squash_merge     = var.allow_squash_merge
  allow_rebase_merge     = var.allow_rebase_merge
  allow_merge_commit     = false
  allow_auto_merge       = true
  delete_branch_on_merge = true
  archive_on_destroy     = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

resource "github_actions_repository_permissions" "this" {
  repository      = github_repository.this.name
  allowed_actions = "selected"

  allowed_actions_config {
    github_owned_allowed = false
    verified_allowed     = false
    patterns_allowed     = var.allowed_actions
  }
}

resource "github_workflow_repository_permissions" "this" {
  repository                       = github_repository.this.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}
