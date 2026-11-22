locals {
  restore_resource_types = {
    Aurora   = "aurora"
    DynamoDB = "dynamodb"
  }
}

# Daily test of the newest recovery point (D2); the validator Lambda and the duration metric live in the platform stack.
resource "aws_backup_restore_testing_plan" "application_databases" {
  count = local.create_plans ? 1 : 0

  name                = "pay_${var.env}_${var.region_short}_application_databases"
  schedule_expression = "cron(0 4 * * ? *)"
  start_window_hours  = 4

  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [aws_backup_vault.this[var.region_name].arn]
    recovery_point_types  = ["CONTINUOUS", "SNAPSHOT"]
    selection_window_days = 1
  }

  tags = var.tags
}

resource "aws_backup_restore_testing_selection" "application_databases" {
  for_each = local.create_plans ? local.restore_resource_types : {}

  name                       = "pay_${var.env}_${var.region_short}_${each.value}"
  restore_testing_plan_name  = aws_backup_restore_testing_plan.application_databases[0].name
  protected_resource_type    = each.key
  iam_role_arn               = aws_iam_role.backup[0].arn
  validation_window_hours    = 1
  restore_metadata_overrides = lookup(var.restore_metadata_overrides, each.key, {})

  protected_resource_conditions {
    string_equals {
      key   = "aws:ResourceTag/backup-tier"
      value = "gold"
    }
  }
}
