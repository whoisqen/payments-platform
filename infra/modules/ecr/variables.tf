variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-west-1."
  }
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "account_id" {
  type        = string
  description = "Registry account (shared-services); replication stays inside it."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "repository_namespace" {
  type        = string
  description = "Namespace of the repositories: images are <namespace>/<name> and the build cache <namespace>-cache/<name>; registry.ecr_repo_prefix in config/platform.yaml."

  validation {
    condition     = can(regex("^[a-z0-9]+([._-][a-z0-9]+)*$", var.repository_namespace))
    error_message = "repository_namespace must be a lower-case ECR repository path segment."
  }
}

variable "repositories" {
  type        = list(string)
  default     = []
  description = "Repository names without prefix (router, locker, drainer, scheduler, control-center); empty in a recovery region where ECR creates replicas."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key that encrypts the repositories of this region; required when repositories is not empty."

  validation {
    condition     = var.kms_key_arn != null || length(var.repositories) == 0
    error_message = "kms_key_arn is required when repositories are created."
  }
}

variable "replication_regions" {
  type        = list(string)
  default     = []
  description = "Recovery regions that receive every image; set only in the primary region, never to the region itself."

  validation {
    condition     = alltrue([for r in var.replication_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))]) && !contains(var.replication_regions, var.region)
    error_message = "replication_regions must be AWS region names and not the module's own region."
  }
}

variable "create_replica_template" {
  type        = bool
  default     = false
  description = "Create the creation template for replicated repositories; a flag because the key ARN may be unknown at plan time."
}

variable "replica_kms_key_arn" {
  type        = string
  default     = null
  description = "Replica KMS key of this region, used by the creation template."

  validation {
    condition     = !var.create_replica_template || var.replica_kms_key_arn != null
    error_message = "replica_kms_key_arn is required when create_replica_template is true."
  }
}

variable "org_id" {
  type        = string
  default     = null
  description = "Organization ID allowed to pull; null keeps pulls inside the account."
}

variable "retention" {
  type = object({
    releases      = number
    prod          = number
    stage         = number
    dev           = number
    signatures    = number
    builds        = number
    untagged_days = number
  })
  description = "Retention: image counts kept per tag class (v*, prod-*, stage-*, dev-* promotions and sha256-* signature artifacts), the latest builds kept under their git sha, and the age in days of untagged images."
  default = {
    releases      = 20
    prod          = 10
    stage         = 5
    dev           = 3
    signatures    = 150
    builds        = 10
    untagged_days = 1
  }

  validation {
    condition     = alltrue([for v in values(var.retention) : v >= 1])
    error_message = "every retention value must be at least 1."
  }
}

variable "cache_repositories" {
  type        = list(string)
  default     = []
  description = "Names of mutable repositories for the docker buildx registry cache (one per image), created as <namespace>-cache/<name>."
}

variable "cache_unused_days" {
  type        = number
  default     = 14
  description = "Days without a pull after which cache and pulled-through images expire."
}

variable "pull_through_cache" {
  type = map(object({
    upstream_registry_url = string
    credential_arn        = optional(string)
  }))
  default     = {}
  description = "Pull-through cache rules by repository prefix; registries that need credentials give a Secrets Manager credential_arn. Registry-wide, so set in one stack per account and region."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
