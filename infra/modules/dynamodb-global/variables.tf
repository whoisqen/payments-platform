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
  default     = "merchant-cell-map"
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

  validation {
    condition     = lookup(var.tags, "backup-tier", "") != "none"
    error_message = "a database cannot opt out of backups."
  }
}

variable "account_id" {
  description = "Account that owns the table; builds the table ARNs of the deny policy without a data source."
  type        = string
}

variable "kms_key_arn" {
  description = "Multi-Region key of the working region."
  type        = string
}

variable "hash_key" {
  description = "Partition key of the merchant-to-cell map."
  type        = string
  default     = "merchant_id"
}

variable "pitr_days" {
  description = "Point-in-time recovery window; 35 is the DynamoDB maximum."
  type        = number
  default     = 35

  validation {
    condition     = var.pitr_days >= 1 && var.pitr_days <= 35
    error_message = "pitr_days must be 1 to 35."
  }
}

variable "deletion_protection" {
  description = "Blocks deletion of the table and its replicas."
  type        = bool
  default     = true
}

variable "recovery_regions" {
  description = "Replica regions with the replica KMS key of each."
  type = map(object({
    kms_key_arn = string
  }))
  default = {}
}

variable "deny_write_regions" {
  description = "Regions where the IAM policy denies writes; null means every replica region, the switch changes it."
  type        = list(string)
  default     = null
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
