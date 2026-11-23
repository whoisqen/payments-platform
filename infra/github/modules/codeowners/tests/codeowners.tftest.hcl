mock_provider "github" {}

variables {
  organization = "org"
  repository   = "payments-platform"
  branch       = "main"
  owners_file  = "../../config/owners.yaml"
  teams = {
    payments_core = "pc"
    security      = "sec"
    platform      = "plat"
    sre           = "sre"
  }
  commit = {
    author  = "a"
    email   = "a@example.invalid"
    message = "m"
  }
}

run "lines" {
  command = plan

  assert {
    condition     = length(split("\n", trimspace(local.codeowners))) == length(local.owners) + 1
    error_message = "one line per mapping plus the header"
  }
  assert {
    condition     = strcontains(local.codeowners, "/vendor/hyperswitch/crates/router/** @org/pc @org/sec")
    error_message = "router code needs payments-core and security"
  }
  assert {
    condition     = strcontains(local.codeowners, "/infra/live/cde-*/** @org/plat @org/sec")
    error_message = "CDE infrastructure needs platform and security"
  }
}

run "personal_account_maps_every_team_to_the_user" {
  command = plan

  variables {
    handles = { payments_core = "@org", security = "@org", platform = "@org", sre = "@org" }
  }

  assert {
    condition     = strcontains(local.codeowners, "/vendor/hyperswitch/crates/router/** @org\n") && !strcontains(local.codeowners, "@org @org")
    error_message = "teams that share a handle appear once per line"
  }
  assert {
    condition     = length(split("\n", trimspace(local.codeowners))) == length(local.owners) + 1
    error_message = "still one line per mapping"
  }
}

run "bad_handle_rejected" {
  command = plan

  variables {
    handles = { security = "org/security" }
  }

  expect_failures = [var.handles]
}

run "committed_file_matches_the_rendered_output" {
  command = plan

  variables {
    organization = "whoisqen"
    handles      = { payments_core = "@whoisqen", security = "@whoisqen", platform = "@whoisqen", sre = "@whoisqen" }
  }

  assert {
    condition     = file("../../../../CODEOWNERS") == local.codeowners
    error_message = "CODEOWNERS at the repository root must be the rendered owners.yaml; regenerate it"
  }
}
