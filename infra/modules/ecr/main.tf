locals {
  # Images live under <namespace>/<name>, the path that the workflows, charts and policies use; the build cache under <namespace>-cache/<name>.
  prefix       = "${var.repository_namespace}/"
  cache_prefix = "${var.repository_namespace}-cache/"

  # CI pushes every build under its git sha, and cosign adds a signature, an SBOM and an attestation as sha256-<digest> tags.
  # Promotion tags v*, prod-*, stage-* and dev-* keep a history to roll back to. An image matching a rule cannot be expired by a lower
  # rule, so a promoted build is kept by its promotion tag even when it is older than the build count; the untagged children of a manifest list are protected by ECR.
  tag_classes = [
    { prefix = "v", keep = var.retention.releases, description = "Keep the release history" },
    { prefix = "prod-", keep = var.retention.prod, description = "Keep the images that ran in prod, for rollback" },
    { prefix = "stage-", keep = var.retention.stage, description = "Keep the images that ran in stage" },
    { prefix = "dev-", keep = var.retention.dev, description = "Keep the images that ran in dev" },
    { prefix = "sha256-", keep = var.retention.signatures, description = "Keep signatures, SBOMs and attestations for every image that is kept" },
  ]
  lifecycle_policy = jsonencode({
    rules = concat(
      [for i, c in local.tag_classes : {
        rulePriority = i + 1
        description  = c.description
        selection    = { tagStatus = "tagged", tagPrefixList = [c.prefix], countType = "imageCountMoreThan", countNumber = c.keep }
        action       = { type = "expire" }
      }],
      [
        {
          rulePriority = 10
          description  = "Keep the latest builds that were never promoted"
          selection    = { tagStatus = "tagged", tagPatternList = ["*"], countType = "imageCountMoreThan", countNumber = var.retention.builds }
          action       = { type = "expire" }
        },
        {
          rulePriority = 11
          description  = "Expire untagged images"
          selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = var.retention.untagged_days }
          action       = { type = "expire" }
        },
      ],
    )
  })

  # Build cache and pulled-through images are disposable: keep what is used, drop what is not pulled.
  cache_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire cache that nobody pulled"
      selection    = { tagStatus = "any", countType = "sinceImagePulled", countUnit = "days", countNumber = var.cache_unused_days }
      action       = { type = "expire" }
    }]
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

# Registry cache of docker buildx (type=registry): the tag is overwritten by every build, so these repositories are mutable.
resource "aws_ecr_repository" "cache" {
  for_each = toset(var.cache_repositories)

  name                 = "${local.cache_prefix}${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = "${local.cache_prefix}${each.key}" })
}

resource "aws_ecr_lifecycle_policy" "cache" {
  for_each = aws_ecr_repository.cache

  repository = each.value.name
  policy     = local.cache_lifecycle_policy
}

# Pull-through cache: nodes pull upstream images from the own registry, which is closer, faster and survives an upstream outage.
resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = var.pull_through_cache

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url
  credential_arn        = each.value.credential_arn
}

# Repositories created by a pull-through pull get the same disposable lifecycle.
resource "aws_ecr_repository_creation_template" "pull_through" {
  for_each = var.pull_through_cache

  prefix               = each.key
  applied_for          = ["PULL_THROUGH_CACHE"]
  image_tag_mutability = "MUTABLE"
  lifecycle_policy     = local.cache_lifecycle_policy
  resource_tags        = var.tags

  # Upstream images are public, so the registry default encryption is enough.
  encryption_configuration {
    encryption_type = "AES256"
  }
}
