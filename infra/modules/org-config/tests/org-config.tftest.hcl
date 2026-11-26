mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::777777777777:role/pay-security-euc1-config-aggregator" }
  }
}

variables {
  region_short           = "euc1"
  region_name            = "eu-central-1"
  regions                = ["eu-central-1", "us-east-1", "us-east-2"]
  admin_account_id       = "777777777777"
  recorder_target_ou_ids = ["ou-ab12-11111111", "ou-ab12-33333333"]
  delivery_bucket_name   = "pay-security-euc1-log-archive"
  delivery_kms_key_arn   = "arn:aws:kms:eu-central-1:555555555555:key/00000000-0000-0000-0000-000000000001"

  tags = {
    team          = "security"
    owner         = "security@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "management_only_delegates" {
  command = apply

  variables {
    mode = "management"
  }

  assert {
    condition     = toset(keys(aws_organizations_delegated_administrator.this)) == toset(["config.amazonaws.com", "config-multiaccountsetup.amazonaws.com", "member.org.stacksets.cloudformation.amazonaws.com"])
    error_message = "Config, its multi-account setup and stack sets are delegated"
  }

  assert {
    condition     = alltrue([for d in aws_organizations_delegated_administrator.this : d.account_id == "777777777777"])
    error_message = "the audit account is the delegated administrator"
  }

  assert {
    condition     = length(aws_config_configuration_aggregator.this) == 0 && length(aws_cloudformation_stack_set.recorder) == 0
    error_message = "management mode builds nothing in the admin account"
  }
}

run "admin_builds_aggregator_recorders_and_pack" {
  command = apply

  variables {
    mode                      = "admin"
    conformance_pack_template = file("../../../policy/config/pci-dss-pack/pci-dss-v4.yaml")
  }

  assert {
    condition     = length(aws_organizations_delegated_administrator.this) == 0
    error_message = "admin mode never delegates"
  }

  assert {
    condition     = aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].all_regions
    error_message = "the aggregator covers every allowed region"
  }

  assert {
    condition = (
      aws_cloudformation_stack_set.recorder[0].permission_model == "SERVICE_MANAGED" &&
      aws_cloudformation_stack_set.recorder[0].call_as == "DELEGATED_ADMIN" &&
      aws_cloudformation_stack_set.recorder[0].auto_deployment[0].enabled &&
      length(aws_cloudformation_stack_set_instance.recorder) == 3
    )
    error_message = "a service-managed, auto-deployed stack set per region"
  }

  assert {
    condition     = jsondecode(aws_cloudformation_stack_set.recorder[0].template_body).Resources.Recorder.Properties.RecordingGroup.AllSupported
    error_message = "recorders record every supported resource"
  }

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.recorder[0].template_body).Resources.DeliveryChannel.DependsOn == "Recorder" &&
      jsondecode(aws_cloudformation_stack_set.recorder[0].template_body).Resources.Recorder.Properties.RoleARN["Fn::If"][0] == "CreateRole"
    )
    error_message = "the delivery channel follows the recorder, and the recorder follows the service-linked role it creates"
  }

  assert {
    condition     = length(aws_config_organization_conformance_pack.this) == 3 && aws_config_organization_conformance_pack.this["us-east-1"].region == "us-east-1"
    error_message = "the PCI DSS pack runs in every region"
  }
}

run "control_tower_recorders_skip_the_stack_set" {
  command = plan

  variables {
    mode                       = "admin"
    recorder_stack_set_enabled = false
  }

  assert {
    condition     = length(aws_cloudformation_stack_set.recorder) == 0 && length(aws_cloudformation_stack_set_instance.recorder) == 0
    error_message = "no stack set when Control Tower owns the recorders"
  }
}

run "stack_set_without_delivery_fails" {
  command = plan

  variables {
    mode                 = "admin"
    delivery_bucket_name = ""
  }

  expect_failures = [aws_cloudformation_stack_set.recorder]
}
