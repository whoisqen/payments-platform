locals {
  management = var.mode == "management"
  admin      = var.mode == "admin"
  name       = "${var.name_prefix}-${var.env}-${var.region_short}"

  regions       = toset(var.regions)
  other_regions = sort(tolist(setsubtract(local.regions, [var.region_name])))

  gd_mgmt  = local.management && var.guardduty_enabled ? local.regions : toset([])
  gd_admin = local.admin && var.guardduty_enabled ? local.regions : toset([])
  gd_features = {
    for p in setproduct(tolist(local.gd_admin), keys(var.guardduty_features)) : "${p[0]}/${p[1]}" => { region = p[0], name = p[1] }
  }

  sh_admin = local.admin && var.securityhub_enabled

  in_mgmt  = local.management && var.inspector_enabled ? local.regions : toset([])
  in_admin = local.admin && var.inspector_enabled ? local.regions : toset([])
  in_members = {
    for p in setproduct(tolist(local.in_admin), var.member_account_ids) : "${p[0]}/${p[1]}" => { region = p[0], account = p[1] }
  }

  mc_mgmt  = local.management && var.macie_enabled ? local.regions : toset([])
  mc_admin = local.admin && var.macie_enabled ? local.regions : toset([])
  mc_job   = local.admin && var.macie_enabled && length(var.cde_account_ids) > 0
}

resource "aws_guardduty_organization_admin_account" "this" {
  for_each = local.gd_mgmt

  region           = each.key
  admin_account_id = var.admin_account_id
}

resource "aws_securityhub_organization_admin_account" "this" {
  count = local.management && var.securityhub_enabled ? 1 : 0

  region           = var.region_name
  admin_account_id = var.admin_account_id
}

resource "aws_inspector2_delegated_admin_account" "this" {
  for_each = local.in_mgmt

  region     = each.key
  account_id = var.admin_account_id
}

resource "aws_macie2_organization_admin_account" "this" {
  for_each = local.mc_mgmt

  region           = each.key
  admin_account_id = var.admin_account_id
}

# Designating the delegated administrator creates its detector, so the admin side reads it instead of creating one.
data "aws_guardduty_detector" "this" {
  for_each = local.gd_admin

  region = each.key
}

resource "aws_guardduty_organization_configuration" "this" {
  for_each = local.gd_admin

  region                           = each.key
  detector_id                      = data.aws_guardduty_detector.this[each.key].id
  auto_enable_organization_members = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each = local.gd_features

  region      = each.value.region
  detector_id = data.aws_guardduty_detector.this[each.value.region].id
  name        = each.value.name
  auto_enable = "ALL"

  dynamic "additional_configuration" {
    for_each = var.guardduty_features[each.value.name]

    content {
      name        = additional_configuration.value
      auto_enable = "ALL"
    }
  }

  depends_on = [aws_guardduty_organization_configuration.this]
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = local.gd_features

  region      = each.value.region
  detector_id = data.aws_guardduty_detector.this[each.value.region].id
  name        = each.value.name
  status      = "ENABLED"

  dynamic "additional_configuration" {
    for_each = var.guardduty_features[each.value.name]

    content {
      name   = additional_configuration.value
      status = "ENABLED"
    }
  }
}

resource "aws_securityhub_finding_aggregator" "this" {
  count = local.sh_admin ? 1 : 0

  region            = var.region_name
  linking_mode      = "SPECIFIED_REGIONS"
  specified_regions = local.other_regions
}

# Central configuration applies the standards in every linked region and account; local configuration would cover only the admin.
resource "aws_securityhub_organization_configuration" "this" {
  count = local.sh_admin ? 1 : 0

  region                = var.region_name
  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.this]
}

resource "aws_securityhub_configuration_policy" "this" {
  count = local.sh_admin ? 1 : 0

  region      = var.region_name
  name        = "${local.name}-securityhub"
  description = "Security Hub on with PCI DSS and AWS standards in every account."

  configuration_policy {
    service_enabled       = true
    enabled_standard_arns = [for s in var.securityhub_standards : "arn:aws:securityhub:${var.region_name}::standards/${s}"]

    security_controls_configuration {
      disabled_control_identifiers = []
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]

  lifecycle {
    precondition {
      condition     = can(regex("^r-[0-9a-z]{4,32}$", var.root_id))
      error_message = "root_id (r-...) is required to associate the Security Hub policy."
    }
  }
}

resource "aws_securityhub_configuration_policy_association" "root" {
  count = local.sh_admin ? 1 : 0

  region    = var.region_name
  target_id = var.root_id
  policy_id = aws_securityhub_configuration_policy.this[0].id
}

resource "aws_inspector2_organization_configuration" "this" {
  for_each = local.in_admin

  region = each.key

  auto_enable {
    ec2         = contains(var.inspector_resource_types, "EC2")
    ecr         = contains(var.inspector_resource_types, "ECR")
    lambda      = contains(var.inspector_resource_types, "LAMBDA")
    lambda_code = contains(var.inspector_resource_types, "LAMBDA_CODE")
  }
}

resource "aws_inspector2_member_association" "this" {
  for_each = local.in_members

  region     = each.value.region
  account_id = each.value.account
}

resource "aws_inspector2_enabler" "this" {
  for_each = local.in_admin

  region         = each.key
  account_ids    = concat([var.admin_account_id], var.member_account_ids)
  resource_types = var.inspector_resource_types

  depends_on = [aws_inspector2_member_association.this]
}

resource "aws_macie2_account" "this" {
  for_each = local.mc_admin

  region                       = each.key
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  status                       = "ENABLED"
}

resource "aws_macie2_organization_configuration" "this" {
  for_each = local.mc_admin

  region      = each.key
  auto_enable = true

  depends_on = [aws_macie2_account.this]
}

# CDE buckets replicate to the recovery regions; scanning the home region finds card data once.
resource "aws_macie2_classification_job" "cde" {
  count = local.mc_job ? 1 : 0

  region              = var.region_name
  name                = "${local.name}-cde-card-data"
  description         = "Daily scan of the CDE S3 buckets for card data that must never be there."
  job_type            = "SCHEDULED"
  initial_run         = true
  sampling_percentage = 100

  schedule_frequency {
    daily_schedule = true
  }

  s3_job_definition {
    bucket_criteria {
      includes {
        and {
          simple_criterion {
            comparator = "EQ"
            key        = "ACCOUNT_ID"
            values     = var.cde_account_ids
          }
        }
      }
    }
  }

  tags = var.tags

  depends_on = [aws_macie2_organization_configuration.this]
}

resource "aws_shield_subscription" "this" {
  count = var.shield_advanced_enabled ? 1 : 0

  auto_renew = "ENABLED"
}
