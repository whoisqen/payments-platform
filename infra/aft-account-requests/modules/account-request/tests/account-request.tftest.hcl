mock_provider "aws" {}

variables {
  name                        = "cde-prod"
  email                       = "aws-pay-cde-prod@example.com"
  ou                          = "Workloads/CDE"
  sso_user                    = { email = "platform@example.com", first_name = "Platform", last_name = "Team" }
  account_customizations_name = "cde"
  tags = {
    environment = "prod", team = "payments-core", owner = "payments-core@example.com", cost-center = "cc-200", cell = "shared"
    pci-scope   = "cde", data-class = "card-data", backup-tier = "gold", managed-by = "aft"
  }
}

run "request_item" {
  command = plan

  assert {
    condition     = jsondecode(aws_dynamodb_table_item.request.item).control_tower_parameters.M.ManagedOrganizationalUnit.S == "Workloads/CDE"
    error_message = "OU is in the request"
  }
}

run "cde_tag_outside_cde_ou_rejected" {
  command = plan

  variables {
    ou = "Workloads/NonCDE"
  }

  expect_failures = [var.tags]
}

run "bad_name_rejected" {
  command = plan

  variables {
    name = "CDE_Prod"
  }

  expect_failures = [var.name]
}
