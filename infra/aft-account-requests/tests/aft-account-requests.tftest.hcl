mock_provider "aws" {}

run "accounts_follow_the_ou_table" {
  command = plan

  assert {
    condition     = toset(output.requested_accounts) == toset(["network", "shared-services", "backup", "cde-dev", "cde-stage", "cde-prod", "platform-dev", "platform-stage", "platform-prod", "sandbox-preview"])
    error_message = "all accounts of the OU table except management, log-archive and audit"
  }
  assert {
    condition     = module.request["cde-prod"].account_name == "cde-prod"
    error_message = "cde-prod is requested"
  }
}
