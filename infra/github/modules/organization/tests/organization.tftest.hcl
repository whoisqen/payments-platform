mock_provider "github" {}

variables {
  billing_email = "x@example.invalid"
}

run "settings" {
  command = plan

  assert {
    condition     = github_organization_settings.this.default_repository_permission == "none" && !github_organization_settings.this.members_can_create_repositories
    error_message = "base permission none and no repository creation by members"
  }
}
