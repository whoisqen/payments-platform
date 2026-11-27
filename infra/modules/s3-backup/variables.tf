variable "env" {
  description = "Environment segment of the resource name."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod", "shared-services"], var.env)
    error_message = "env must be dev, stage, prod or shared-services."
  }
}

variable "region_short" {
  description = "Short region code of the provider region, for example euc1 (name pay-<env>-<region-short>-<component>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "component" {
  description = "Component segment of the bucket name, for example backup or event-archive."
  type        = string
  default     = "backup"
}

variable "region_role" {
  description = "working creates the source, the locked destination buckets and replication; recovery creates one locked bucket."
  type        = string
  default     = "working"

  validation {
    condition     = contains(["working", "recovery"], var.region_role)
    error_message = "region_role must be working or recovery."
  }
}

variable "region_name" {
  description = "AWS region of the provider; the key of the local bucket."
  type        = string
}

variable "tags" {
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }

  validation {
    condition = (
      contains(["payments-core", "platform", "security", "data"], lookup(var.tags, "team", "")) &&
      contains(["cde", "connected", "out-of-scope"], lookup(var.tags, "pci-scope", "")) &&
      contains(["card-data", "pii", "internal", "public"], lookup(var.tags, "data-class", "")) &&
      contains(["gold", "silver", "bronze", "none"], lookup(var.tags, "backup-tier", ""))
    )
    error_message = "tags team, pci-scope, data-class or backup-tier is outside the section 22.1 schema."
  }
}

variable "kms_key_arn" {
  description = "Key of the local bucket; created by the kms module."
  type        = string
}

variable "recovery_regions" {
  description = "Destination regions of a working stack: short code and replica KMS key of each."
  type = map(object({
    short       = string
    kms_key_arn = string
  }))
  default = {}
}

variable "object_lock_mode" {
  description = "Default Object Lock mode of every copy."
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be COMPLIANCE or GOVERNANCE."
  }
}

variable "object_lock_days" {
  description = "Default retention in days; it must not exceed expire_after_days."
  type        = number
  default     = 35
}

variable "lifecycle_prefixes" {
  description = "Prefixes of object backups that move to colder tiers and expire."
  type        = list(string)
  default     = ["backups/", "exports/", "events/"]
}

variable "cold_after_days" {
  description = "First colder tier (Glacier Instant Retrieval) after this many days (D5)."
  type        = number
  default     = 7
}

variable "colder_after_days" {
  description = "Still colder tier (Glacier Flexible Retrieval) after this many days (D5)."
  type        = number
  default     = 14

  validation {
    condition     = var.colder_after_days > var.cold_after_days
    error_message = "colder_after_days must be greater than cold_after_days."
  }
}

variable "expire_after_days" {
  description = "Retention of object backups; 35 days like every other store (D3)."
  type        = number
  default     = 35
}

variable "archive_prefix" {
  description = "Prefix of the monthly archive, kept in the coldest tier."
  type        = string
  default     = "archive/monthly/"
}

variable "archive_expire_days" {
  description = "7 years of financial reporting."
  type        = number
  default     = 2555
}

variable "bucket_policy_statements" {
  description = "Extra statements for the local bucket, for example sink_bucket_policy_statements of the msk module."
  type        = list(any)
  default     = []
}

variable "alarm_actions" {
  description = "SNS topic ARNs of the replication latency alarm."
  type        = list(string)
  default     = []
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
