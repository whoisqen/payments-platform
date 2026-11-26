locals {
  types = {
    "."               = "SERVICE_CONTROL_POLICY"
    "tag-policies"    = "TAG_POLICY"
    "backup-policies" = "BACKUP_POLICY"
  }

  files = merge([
    for dir, type in local.types : {
      for f in fileset("${var.policy_dir}/${dir}", "*.json") : trimsuffix(f, ".json") => {
        type    = type
        content = file("${var.policy_dir}/${dir}/${f}")
      }
    }
  ]...)

  attachments = merge([
    for name, targets in var.policy_targets : {
      for t in targets : "${name}/${t}" => { policy = name, target = t }
    }
  ]...)

  rcp = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyAccessFromOutsideTheOrganization"
      Effect    = "Deny"
      Principal = "*"
      Action    = var.rcp_actions
      Resource  = "*"
      # Service principals deliver logs and replicate on behalf of the organization, so they are exempt.
      Condition = {
        StringNotEqualsIfExists = { "aws:PrincipalOrgID" = var.organization_id }
        BoolIfExists            = { "aws:PrincipalIsAWSService" = "false" }
      }
    }]
  }
}

resource "aws_organizations_policy" "this" {
  for_each = local.files

  name        = "${var.name_prefix}-${each.key}"
  description = "policy/scp ${each.key} (${each.value.type})"
  type        = each.value.type
  content     = each.value.content

  tags = var.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.policy_targets), each.key)
      error_message = "policy_targets has no entry for ${each.key}; list its targets or [] to keep it unattached."
    }
  }
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachments

  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = var.target_ids[each.value.target]

  lifecycle {
    precondition {
      condition     = contains(keys(var.target_ids), each.value.target)
      error_message = "target ${each.value.target} is not a key of target_ids."
    }
  }
}

resource "aws_organizations_policy" "rcp" {
  count = length(var.rcp_targets) > 0 ? 1 : 0

  name        = "${var.name_prefix}-cde-deny-outside-org"
  description = "Deny S3, KMS and Secrets Manager access from principals outside the organization."
  type        = "RESOURCE_CONTROL_POLICY"
  content     = jsonencode(local.rcp)

  tags = var.tags
}

resource "aws_organizations_policy_attachment" "rcp" {
  for_each = toset(var.rcp_targets)

  policy_id = aws_organizations_policy.rcp[0].id
  target_id = var.target_ids[each.key]
}
