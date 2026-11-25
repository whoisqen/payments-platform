variable "name_prefix" {
  description = "Prefix of the resource names."
  type        = string
  default     = "pay"
}

variable "env" {
  description = "Environment segment of the resource name."
  type        = string
  default     = "management"
}

variable "region_short" {
  description = "Short region code (name pay-<env>-<region-short>-<component>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "region_name" {
  description = "Home region of the trail and its log group."
  type        = string
}

variable "component" {
  description = "Component segment of the names."
  type        = string
  default     = "org-trail"
}

variable "account_id" {
  description = "Management account that owns the trail."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "s3_bucket_name" {
  description = "Log archive bucket (output bucket_name of log-archive)."
  type        = string
}

variable "s3_key_prefix" {
  description = "Prefix of the trail in the bucket (prefixes.cloudtrail of log-archive)."
  type        = string
  default     = "cloudtrail"
}

variable "s3_kms_key_arn" {
  description = "Key of the log archive in the log-archive account (output kms_key_arn of log-archive)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.s3_kms_key_arn))
    error_message = "s3_kms_key_arn must be a KMS key ARN."
  }
}

variable "log_retention_days" {
  description = "Retention of the CloudWatch Logs copy; the archive keeps the records for a year or more."
  type        = number
  default     = 90
}

variable "cde_s3_bucket_prefixes" {
  description = "Bucket name prefixes of the CDE accounts whose S3 object-level events the trail records; selectors cannot filter by account."
  type        = list(string)

  validation {
    condition     = length(var.cde_s3_bucket_prefixes) > 0 && alltrue([for p in var.cde_s3_bucket_prefixes : can(regex("^[a-z0-9][a-z0-9.-]*$", p))])
    error_message = "cde_s3_bucket_prefixes needs at least one bucket name prefix (lower-case, no arn: part)."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the log group key is deleted."
  type        = number
  default     = 30
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
