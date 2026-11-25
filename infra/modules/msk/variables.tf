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
  default     = "msk"
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

variable "account_id" {
  description = "Account that owns the cluster; scopes the trust of the sink role."
  type        = string
}

variable "kms_key_arn" {
  description = "Key that encrypts broker volumes."
  type        = string
}

variable "client_subnets" {
  description = "One subnet per AZ; brokers spread evenly over them."
  type        = list(string)

  validation {
    condition     = length(var.client_subnets) == 3
    error_message = "client_subnets must list one subnet in each of three AZs."
  }
}

variable "security_group_ids" {
  description = "Security groups of the brokers."
  type        = list(string)
}

variable "kafka_version" {
  description = "Kafka version of brokers and configuration."
  type        = string
  default     = "3.9.x"
}

variable "broker_count" {
  description = "Brokers of the cluster; a multiple of three keeps the AZs even."
  type        = number
  default     = 9

  validation {
    condition     = var.broker_count % 3 == 0 && var.broker_count >= 3
    error_message = "broker_count must be a multiple of 3."
  }
}

variable "instance_type" {
  description = "Broker instance type."
  type        = string
  default     = "kafka.m7g.xlarge"
}

variable "volume_size_gb" {
  description = "EBS volume per broker."
  type        = number
  default     = 2000
}

variable "retention_hours" {
  description = "Broker log retention; 168 is 7 days, the rest lives in the S3 archive."
  type        = number
  default     = 168
}

variable "logs_kms_key_arn" {
  description = "Key of the broker log group; its policy must admit logs.amazonaws.com."
  type        = string
}

variable "log_retention_days" {
  description = "Days the broker logs stay in CloudWatch."
  type        = number
  default     = 30
}

variable "enhanced_monitoring" {
  description = "CloudWatch metric level; per partition in prod and stage, DEFAULT in dev (the extra metrics are billed)."
  type        = string
  default     = "PER_TOPIC_PER_PARTITION"

  validation {
    condition     = contains(["DEFAULT", "PER_BROKER", "PER_TOPIC_PER_BROKER", "PER_TOPIC_PER_PARTITION"], var.enhanced_monitoring)
    error_message = "enhanced_monitoring must be an MSK monitoring level."
  }
}

variable "sink_bucket_arn" {
  description = "Event archive bucket created by s3-backup."
  type        = string
}

variable "sink_prefix" {
  description = "Prefix the S3 sink writes under."
  type        = string
  default     = "events"
}

variable "sink_kms_key_arn" {
  description = "Key of the archive bucket."
  type        = string
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
