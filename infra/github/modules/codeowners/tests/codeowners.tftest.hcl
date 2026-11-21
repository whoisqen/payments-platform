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
