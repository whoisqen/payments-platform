locals {
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1", "us-east-2" = "use2" }[var.region]
  prefix       = "pay-${var.environment}-${local.region_short}-"

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = var.untagged_expire_days }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the latest tagged images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.keep_tagged_images }
        action       = { type = "expire" }
      },
    ]
  })

  pull_policy = var.org_id == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OrganizationPull"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.org_id } }
    }]
  })
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${local.prefix}${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = "${local.prefix}${each.key}" })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository_policy" "pull" {
  for_each = var.org_id == null ? {} : aws_ecr_repository.this

  repository = each.value.name
  policy     = local.pull_policy
}

# Registry-wide setting, so it is owned by the primary region only.
resource "aws_ecr_registry_scanning_configuration" "this" {
  count = length(var.replication_regions) > 0 ? 1 : 0

  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"

    repository_filter {
      filter      = "${local.prefix}*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_ecr_replication_configuration" "this" {
  count = length(var.replication_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_regions

        content {
          region      = destination.value
          registry_id = var.account_id
        }
      }

      repository_filter {
        filter      = local.prefix
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# Replicas are created by ECR itself; the template gives them the same settings and the replica KMS key.
resource "aws_ecr_repository_creation_template" "replica" {
  count = var.create_replica_template ? 1 : 0

  prefix               = local.prefix
  applied_for          = ["REPLICATION"]
  image_tag_mutability = "IMMUTABLE"
  lifecycle_policy     = local.lifecycle_policy
  resource_tags        = var.tags

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.replica_kms_key_arn
  }
}
