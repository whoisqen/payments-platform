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
  description = "Component segment of the name, for example memorydb-cell-0."
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

  validation {
    condition     = lookup(var.tags, "backup-tier", "") != "none"
    error_message = "a database cannot opt out of backups."
  }
}

variable "kms_key_arn" {
  description = "Key of the cell that encrypts data and snapshots; created by the kms module."
  type        = string
}

variable "subnet_ids" {
  description = "One data subnet per AZ; MemoryDB spreads the nodes of each shard over them."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) == 3
    error_message = "subnet_ids must list one subnet in each of three AZs."
  }
}

variable "security_group_ids" {
  description = "Security groups of the cluster."
  type        = list(string)
}

variable "node_type" {
  description = "Node type of every shard member."
  type        = string
  default     = "db.r7g.xlarge"
}

variable "num_shards" {
  description = "Shards of the cluster."
  type        = number
  default     = 2
}

variable "num_replicas_per_shard" {
  description = "Replicas per shard; 2 puts one primary and two replicas in three AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.num_replicas_per_shard == 2
    error_message = "three AZs need exactly two replicas per shard."
  }
}

variable "engine_version" {
  description = "Redis OSS API version."
  type        = string
  default     = "7.1"
}

variable "parameter_group_family" {
  description = "Parameter group family that matches engine_version."
  type        = string
  default     = "memorydb_redis7"
}

variable "snapshot_window" {
  description = "Daily UTC window of the native snapshot; hourly snapshots come from the backup module."
  type        = string
  default     = "02:00-03:00"
}

variable "snapshot_retention_days" {
  description = "Retention of native snapshots; 35 days as every other store."
  type        = number
  default     = 35
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "users" {
  description = "ACL users keyed by name with their access string; they authenticate with IAM, so no password exists."
  type        = map(string)
}

variable "sns_topic_arn" {
  description = "Topic for cluster events; null disables notifications."
  type        = string
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
