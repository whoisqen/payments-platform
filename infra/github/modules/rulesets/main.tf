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

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    required_signatures     = true

    pull_request {
      required_approving_review_count   = var.approvals
      require_code_owner_review         = true
      dismiss_stale_reviews_on_push     = true
      require_last_push_approval        = true
      required_review_thread_resolution = true
    }

    merge_queue {
      merge_method                      = "SQUASH"
      grouping_strategy                 = "ALLGREEN"
      min_entries_to_merge              = 1
      max_entries_to_merge              = 5
      min_entries_to_merge_wait_minutes = 5
      max_entries_to_build              = 5
      check_response_timeout_minutes    = 60
    }

    required_status_checks {
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
    actor_id    = var.tagging_app_id
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  rules {
    creation         = true
    update           = true
    deletion         = true
    non_fast_forward = true
  }
}
