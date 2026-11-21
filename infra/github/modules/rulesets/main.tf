resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = var.repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  dynamic "bypass_actors" {
    for_each = var.main_admin_bypass ? [1] : []
    content {
      actor_id    = 5
      actor_type  = "RepositoryRole"
      bypass_mode = "pull_request"
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    required_signatures     = var.require_signatures

    pull_request {
      required_approving_review_count   = var.approvals
      require_code_owner_review         = true
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = true
      required_review_thread_resolution = true
    }

    dynamic "merge_queue" {
      for_each = var.merge_queue ? [1] : []
      content {
        merge_method                      = "SQUASH"
        grouping_strategy                 = "ALLGREEN"
        min_entries_to_merge              = 1
        max_entries_to_merge              = 5
        min_entries_to_merge_wait_minutes = 5
        max_entries_to_build              = 5
        check_response_timeout_minutes    = 60
      }
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = var.required_checks
          content {
            context = required_check.value
          }
        }
      }
    }
  }
}

# Only the tagging workflow creates v* tags; nobody deletes or moves them.
resource "github_repository_ruleset" "version_tags" {
  name        = "version-tags"
  repository  = var.repository
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = var.tag_bypass.actor_id
    actor_type  = var.tag_bypass.actor_type
    bypass_mode = "always"
  }

  rules {
    creation         = true
    update           = true
    deletion         = true
    non_fast_forward = true
  }
}
