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

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "component" {
  description = "Component segment of the name."
  type        = string
  default     = "clickhouse"
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

variable "kms_key_arn" {
  description = "Customer managed key of the backup bucket; created by the kms module."
  type        = string
}

variable "backup_bucket_arn" {
  description = "Bucket of the s3-backup module that receives the clickhouse-backup archives."
  type        = string
}

variable "backup_prefix" {
  description = "Key prefix of the backups; it must be one of lifecycle_prefixes of the bucket so retention applies."
  type        = string
  default     = "backups/clickhouse/"

  validation {
    condition     = endswith(var.backup_prefix, "/")
    error_message = "backup_prefix must end with a slash."
  }
}

variable "archive_bucket_arn" {
  description = "Event archive bucket read during restore to catch up from the last backup (D3, D4)."
  type        = string
}

variable "archive_kms_key_arn" {
  description = "Key of the event archive bucket; decrypt only."
  type        = string
}

variable "archive_prefix" {
  description = "Key prefix of the event archive that a catch-up reads."
  type        = string
  default     = "events/"

  validation {
    condition     = endswith(var.archive_prefix, "/")
    error_message = "archive_prefix must end with a slash."
  }
}

variable "cluster_name" {
  description = "EKS cluster whose Pod Identity agent hands the role to the backup pods."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ClickHouse workloads."
  type        = string
  default     = "clickhouse"
}

variable "service_account" {
  description = "Service account of the clickhouse-backup CronJob and the restore Job."
  type        = string
  default     = "clickhouse-backup"
}

variable "rpo_minutes" {
  description = "Analytics recovery point objective; the gap since the last backup is closed from the event archive."
  type        = number
  default     = 15

  validation {
    condition     = var.rpo_minutes > 0 && var.rpo_minutes <= 15
    error_message = "rpo_minutes must be between 1 and 15 (analytics RPO)."
  }
}

variable "rto_hours" {
  description = "Analytics recovery time objective."
  type        = number
  default     = 4

  validation {
    condition     = var.rto_hours > 0 && var.rto_hours <= 4
    error_message = "rto_hours must be greater than 0 and at most 4 (analytics RTO)."
  }
}

variable "backup_interval_minutes" {
  description = "Interval of the backup CronJob; hourly (D3)."
  type        = number
  default     = 60

  validation {
    condition     = var.backup_interval_minutes >= 15 && var.backup_interval_minutes <= 60 && 60 % var.backup_interval_minutes == 0
    error_message = "backup_interval_minutes must divide 60 and be between 15 and 60 (hourly at most, D3)."
  }
}

variable "compression_format" {
  description = "Compression of the backup archives."
  type        = string
  default     = "zstd"

  validation {
    condition     = var.compression_format == "zstd"
    error_message = "compression_format must be zstd (D4)."
  }
}

variable "compression_level" {
  description = "zstd level; low keeps restore inside the RTO (D4)."
  type        = number
  default     = 1

  validation {
    condition     = var.compression_level >= 1 && var.compression_level <= 3
    error_message = "compression_level must be a low zstd level, 1 to 3."
  }
}

variable "retention_days" {
  description = "Retention of backups; must match the bucket lifecycle (D3)."
  type        = number
  default     = 35

  validation {
    condition     = var.retention_days == 35
    error_message = "retention_days must be 35 (D3)."
  }
}

variable "max_missed_backups" {
  description = "Backup intervals without a success before the backup age alarm fires."
  type        = number
  default     = 2

  validation {
    condition     = var.max_missed_backups >= 1 && var.max_missed_backups <= 3
    error_message = "max_missed_backups must be 1 to 3."
  }
}

variable "metric_namespace" {
  description = "CloudWatch namespace of the metrics the backup and restore jobs publish."
  type        = string
  default     = "Payments/ClickHouse"
}

variable "alarm_actions" {
  description = "SNS topic ARNs of the alarms."
  type        = list(string)
  default     = []
}
