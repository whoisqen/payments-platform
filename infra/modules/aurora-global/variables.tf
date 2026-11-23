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
  description = "Component segment of the name, for example aurora-cell-0 or aurora-locker."
  type        = string
}

variable "region_role" {
  description = "working is the only writing region; recovery creates one headless cluster that joins an existing global cluster."
  type        = string
  default     = "working"

  validation {
    condition     = contains(["working", "recovery"], var.region_role)
    error_message = "region_role must be working or recovery."
  }
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
  description = "Multi-Region primary key (working) or replica key (recovery) that encrypts the cluster; created by the kms module."
  type        = string
}

variable "primary_region" {
  description = "Region of the writer cluster; source of the encrypted secondary clusters."
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL version; headless secondaries need at least 13.4."
  type        = string
  default     = "16.8"
}

variable "parameter_group_family" {
  description = "Parameter group family that matches engine_version."
  type        = string
  default     = "aurora-postgresql16"
}

variable "db_subnet_group_name" {
  description = "DB subnet group of the provider region."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups of the cluster; only locker or router pods reach it."
  type        = list(string)
}

variable "availability_zones" {
  description = "Three AZs of the provider region; the writer takes writer_az, readers the rest."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "availability_zones must list exactly three AZs."
  }
}

variable "writer_az" {
  description = "AZ of the writer; differs between cells so one AZ loss never takes every writer."
  type        = string
}

variable "writer_instance_class" {
  description = "Instance class of the writer."
  type        = string
  default     = "db.r7g.12xlarge"
}

variable "reader_instance_class" {
  description = "Instance class of the readers."
  type        = string
  default     = "db.r7g.4xlarge"
}

variable "reader_count" {
  description = "Number of readers in the working region."
  type        = number
  default     = 1

  validation {
    condition     = var.reader_count >= 0 && var.reader_count <= 2
    error_message = "reader_count must be 0, 1 or 2 (one reader per spare AZ)."
  }
}

variable "backup_retention_days" {
  description = "Automated backup and PITR window; 35 is the Aurora maximum."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be 7 to 35."
  }
}

variable "backup_window" {
  description = "Daily UTC window of the automated backup."
  type        = string
  default     = "01:00-02:00"
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window."
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "hyperswitch"
}

variable "deletion_protection" {
  description = "Blocks deletion of clusters; turn off only for dev."
  type        = bool
  default     = true
}

variable "proxy_subnet_ids" {
  description = "Subnets of the RDS Proxy endpoint."
  type        = list(string)
}

variable "proxy_security_group_ids" {
  description = "Security groups of the RDS Proxy."
  type        = list(string)
}

variable "recovery_regions" {
  description = "Headless secondary clusters of a working region, keyed by region: short code, replica KMS key, subnet group and security groups there."
  type = map(object({
    short              = string
    kms_key_arn        = string
    db_subnet_group    = string
    security_group_ids = list(string)
  }))
  default = {}
}

variable "global_cluster_identifier" {
  description = "Existing global cluster that a recovery cluster joins; required when region_role is recovery."
  type        = string
  default     = null
}

variable "recovery_instance_count" {
  description = "Instances created in a recovery region; 0 keeps it storage only, set at the switch."
  type        = number
  default     = 0
}

variable "lag_alarm_threshold_ms" {
  description = "Alarm above this global replication lag; the RPO budget is 10 s."
  type        = number
  default     = 5000
}

variable "region_name" {
  description = "AWS region of the provider; the key of the local parameter group and of a recovery cluster."
  type        = string
}

variable "proxy_secret_arn" {
  description = "Database secret the proxy of a recovery region reads; the working role uses the RDS-managed master secret."
  type        = string
  default     = null
}

variable "alarm_actions" {
  description = "SNS topic ARNs of the lag alarm per region key; the topic must live in the alarm region."
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
