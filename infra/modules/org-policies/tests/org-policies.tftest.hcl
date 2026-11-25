mock_provider "aws" {}

variables {
  policy_dir      = "../../../policy/scp"
  organization_id = "o-abcdefghij"

  target_ids = {
    root             = "r-ab12"
    security         = "ou-ab12-11111111"
    infrastructure   = "ou-ab12-22222222"
    workloads_cde    = "ou-ab12-33333333"
    workloads_noncde = "ou-ab12-44444444"
  }

  policy_targets = {
    "security-baseline"                     = ["workloads_cde", "workloads_noncde", "infrastructure"]
    "region-allow-list"                     = ["root"]
    "deny-tag-edit"                         = ["workloads_cde", "workloads_noncde"]
    "deny-dynamodb-writes-recovery-regions" = ["workloads_cde", "workloads_noncde"]
    "required-tags"                         = ["workloads_cde", "workloads_noncde"]
    "backup-tiers"                          = ["workloads_cde"]
  }

  tags = {
    team          = "security"
    owner         = "security@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "every_document_becomes_a_policy_of_its_type" {
  command = apply

  assert {
    condition     = length(aws_organizations_policy.this) == 6
    error_message = "four SCPs, one tag policy and one backup policy"
  }

  assert {
    condition = (
      aws_organizations_policy.this["security-baseline"].type == "SERVICE_CONTROL_POLICY" &&
      aws_organizations_policy.this["required-tags"].type == "TAG_POLICY" &&
      aws_organizations_policy.this["backup-tiers"].type == "BACKUP_POLICY"
    )
    error_message = "the type follows the directory of the document"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["security-baseline"].content) == jsondecode(file("../../../policy/scp/security-baseline.json"))
    error_message = "documents are attached unchanged"
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 11 && aws_organizations_policy_attachment.this["region-allow-list/root"].target_id == "r-ab12"
    error_message = "one attachment per policy and target"
  }
}

run "rcp_denies_outside_principals_on_the_cde_ou" {
  command = apply

  assert {
    condition     = aws_organizations_policy.rcp[0].type == "RESOURCE_CONTROL_POLICY" && aws_organizations_policy_attachment.rcp["workloads_cde"].target_id == "ou-ab12-33333333"
    error_message = "the RCP is attached to the CDE OU"
  }

  assert {
    condition = (
      jsondecode(aws_organizations_policy.rcp[0].content).Statement[0].Condition.StringNotEqualsIfExists["aws:PrincipalOrgID"] == "o-abcdefghij" &&
      jsondecode(aws_organizations_policy.rcp[0].content).Statement[0].Condition.BoolIfExists["aws:PrincipalIsAWSService"] == "false" &&
      toset(jsondecode(aws_organizations_policy.rcp[0].content).Statement[0].Action) == toset(["s3:*", "kms:*", "secretsmanager:*"])
    )
    error_message = "the RCP denies S3, KMS and Secrets Manager outside the organization, service principals exempt"
  }
}

run "rcp_is_optional" {
  command = plan

  variables {
    rcp_targets = []
  }

  assert {
    condition     = length(aws_organizations_policy.rcp) == 0 && length(aws_organizations_policy_attachment.rcp) == 0
    error_message = "no RCP without targets"
  }
}

run "a_document_without_targets_fails" {
  command = plan

  variables {
    policy_targets = { "security-baseline" = ["root"] }
  }

  expect_failures = [aws_organizations_policy.this]
}

run "unknown_target_fails" {
  command = plan

  variables {
    policy_targets = {
      "security-baseline"                     = ["nowhere"]
      "region-allow-list"                     = []
      "deny-tag-edit"                         = []
      "deny-dynamodb-writes-recovery-regions" = []
      "required-tags"                         = []
      "backup-tiers"                          = []
    }
  }

  expect_failures = [aws_organizations_policy_attachment.this]
}
