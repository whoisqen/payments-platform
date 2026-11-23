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

variable "keep_tagged_images" {
  type        = number
  default     = 50
  description = "Tagged images kept per repository."
}

variable "untagged_expire_days" {
  type        = number
  default     = 14
  description = "Days after which untagged images expire."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
