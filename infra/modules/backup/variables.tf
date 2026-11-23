variable "env" {
  description = "Environment segment of the resource name."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env must be dev, stage or prod."
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
  description = "Component segment of the name."
  type        = string
  default     = "backup"
}

variable "region_role" {
  description = "working owns vaults in every region and the plans; recovery owns one vault in the provider region."
  type        = string
  default     = "working"

  validation {
    condition     = contains(["working", "recovery"], var.region_role)
    error_message = "region_role must be working or recovery."
  }
}

variable "region_name" {
  description = "AWS region of the provider; the key of the local vault."
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
  description = "Backup-account key of the local vault; never the production key."
  type        = string
}

variable "data_kms_key_arns" {
  description = "Keys of the protected resources that the backup role must use for copies and restores."
  type        = list(string)
  default     = []
}

variable "recovery_regions" {
  description = "Vaults that receive copies in us-east-1 and us-east-2: short code and backup-account replica key."
  type = map(object({
    short       = string
    kms_key_arn = string
  }))
  default = {}
}

variable "copy_vault_arns" {
  description = "Destination vaults owned by another stack, merged with the vaults of this one; used when plans and vaults live in different accounts."
  type        = map(string)
  default     = {}
}

variable "source_account_ids" {
  description = "Accounts allowed to copy into the vaults; empty keeps the vaults closed."
  type        = list(string)
  default     = []
}

variable "create_plans" {
  description = "false in a backup-account stack that only holds vaults."
  type        = bool
  default     = true
}

variable "vault_lock_enabled" {
  description = "Vault Lock in compliance mode; mandatory in prod."
  type        = bool
  default     = true

  validation {
    condition     = var.vault_lock_enabled || var.env != "prod"
    error_message = "prod vaults must be locked."
  }
}

variable "vault_lock_cooling_off_days" {
  description = "Days before the lock becomes immutable; 3 is the AWS minimum for compliance mode."
  type        = number
  default     = 3

  validation {
    condition     = var.vault_lock_cooling_off_days >= 3
    error_message = "compliance mode needs at least 3 days of cooling-off."
  }
}

variable "min_retention_days" {
  description = "Shortest retention the lock accepts; must not exceed the shortest rule (bronze) or jobs fail."
  type        = number
  default     = 7

  validation {
    condition     = var.min_retention_days <= var.bronze_retention_days
    error_message = "min_retention_days above bronze_retention_days would reject the bronze rule."
  }
}

variable "max_retention_days" {
  description = "Longest retention the lock accepts; must cover the 7-year archive."
  type        = number
  default     = 2555

  validation {
    condition     = var.max_retention_days >= var.archive_retention_days
    error_message = "max_retention_days below archive_retention_days would reject the monthly rule."
  }
}

variable "snapshot_retention_days" {
  description = "Retention of hourly snapshots and continuous recovery points; 35 is the continuous-backup maximum."
  type        = number
  default     = 35

  validation {
    condition     = var.snapshot_retention_days <= 35
    error_message = "continuous backup cannot be kept longer than 35 days."
  }
}

variable "archive_retention_days" {
  description = "Retention of the monthly snapshot, 7 years."
  type        = number
  default     = 2555
}

variable "bronze_retention_days" {
  description = "Retention of bronze daily backups."
  type        = number
  default     = 7
}

variable "restore_metadata_overrides" {
  description = "Restore metadata of the daily restore test per resource type (Aurora, DynamoDB), for example subnet group and security groups of the isolated VPC."
  type        = map(map(string))
  default     = {}
}

variable "sns_topic_arns" {
  description = "Notification topic per vault region; a region without a topic gets no notifications."
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
