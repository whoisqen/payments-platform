locals {
  management = var.mode == "management"
  admin      = var.mode == "admin"
  name       = "${var.name_prefix}-${var.env}-${var.region_short}-config"

  delegated_services = local.management ? toset([
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
  ]) : toset([])

  stack_set   = local.admin && var.recorder_stack_set_enabled
  pack        = local.admin && var.conformance_pack_template != ""
  pack_region = local.pack ? toset(var.regions) : toset([])

  # Global resources (IAM) are recorded once, in the home region, so the other regions do not duplicate them.
  recorder_template = {
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Config recorder and delivery channel to the log archive (${local.name})."
    Parameters = {
      HomeRegion       = { Type = "String" }
      BucketName       = { Type = "String" }
      KeyPrefix        = { Type = "String" }
      KmsKeyArn        = { Type = "String" }
      CreateLinkedRole = { Type = "String", AllowedValues = ["true", "false"] }
    }
    Conditions = {
      IsHomeRegion = { "Fn::Equals" = [{ Ref = "AWS::Region" }, { Ref = "HomeRegion" }] }
      CreateRole   = { "Fn::And" = [{ Condition = "IsHomeRegion" }, { "Fn::Equals" = [{ Ref = "CreateLinkedRole" }, "true"] }] }
    }
    Resources = {
      ConfigServiceLinkedRole = {
        Type       = "AWS::IAM::ServiceLinkedRole"
        Condition  = "CreateRole"
        Properties = { AWSServiceName = "config.amazonaws.com" }
      }
      Recorder = {
        Type = "AWS::Config::ConfigurationRecorder"
        Properties = {
          Name = "default"
          # Referencing the role in the true branch orders the recorder after it; the false branch never resolves the conditional resource.
          RoleARN = { "Fn::If" = [
            "CreateRole",
            { "Fn::Sub" = "arn:aws:iam::$${AWS::AccountId}:role/aws-service-role/config.amazonaws.com/$${ConfigServiceLinkedRole}" },
            { "Fn::Sub" = "arn:aws:iam::$${AWS::AccountId}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" },
          ] }
          RecordingGroup = {
            AllSupported               = true
            IncludeGlobalResourceTypes = { "Fn::If" = ["IsHomeRegion", true, false] }
          }
        }
      }
      DeliveryChannel = {
        Type      = "AWS::Config::DeliveryChannel"
        DependsOn = "Recorder"
        Properties = {
          Name         = "default"
          S3BucketName = { Ref = "BucketName" }
          S3KeyPrefix  = { Ref = "KeyPrefix" }
          S3KmsKeyArn  = { Ref = "KmsKeyArn" }
          ConfigSnapshotDeliveryProperties = {
            DeliveryFrequency = "TwentyFour_Hours"
          }
        }
      }
    }
  }
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each = local.delegated_services

  account_id        = var.admin_account_id
  service_principal = each.key
}

resource "aws_iam_role" "aggregator" {
  count = local.admin ? 1 : 0

  name = "${local.name}-aggregator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.admin_account_id } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  count = local.admin ? 1 : 0

  role       = aws_iam_role.aggregator[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "this" {
  count = local.admin ? 1 : 0

  name = "${local.name}-org"

  organization_aggregation_source {
    regions  = var.regions
    role_arn = aws_iam_role.aggregator[0].arn
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.aggregator]
}

resource "aws_cloudformation_stack_set" "recorder" {
  count = local.stack_set ? 1 : 0

  name             = "${local.name}-recorder"
  description      = "Config recorder in every account of the organization."
  permission_model = "SERVICE_MANAGED"
  call_as          = "DELEGATED_ADMIN"
  capabilities     = ["CAPABILITY_IAM"]
  template_body    = jsonencode(local.recorder_template)

  parameters = {
    HomeRegion       = var.region_name
    BucketName       = var.delivery_bucket_name
    KeyPrefix        = var.delivery_key_prefix
    KmsKeyArn        = var.delivery_kms_key_arn
    CreateLinkedRole = tostring(var.create_service_linked_role)
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  operation_preferences {
    failure_tolerance_percentage = 10
    max_concurrent_percentage    = 50
    region_concurrency_type      = "PARALLEL"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [administration_role_arn]

    precondition {
      condition     = var.delivery_bucket_name != "" && can(regex("^arn:aws:kms:", var.delivery_kms_key_arn)) && length(var.recorder_target_ou_ids) > 0
      error_message = "the recorder stack set needs delivery_bucket_name, delivery_kms_key_arn and recorder_target_ou_ids."
    }
  }
}

resource "aws_cloudformation_stack_set_instance" "recorder" {
  for_each = local.stack_set ? toset(var.regions) : toset([])

  stack_set_name            = aws_cloudformation_stack_set.recorder[0].name
  stack_set_instance_region = each.key
  call_as                   = "DELEGATED_ADMIN"

  deployment_targets {
    organizational_unit_ids = var.recorder_target_ou_ids
  }
}

resource "aws_config_organization_conformance_pack" "this" {
  for_each = local.pack_region

  region            = each.key
  name              = var.conformance_pack_name
  template_body     = var.conformance_pack_template
  excluded_accounts = var.conformance_pack_excluded_accounts

  depends_on = [aws_cloudformation_stack_set_instance.recorder]
}
