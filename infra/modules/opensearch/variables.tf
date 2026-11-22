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
  description = "Component segment of the domain name; the whole name is limited to 28 characters."
  type        = string
  default     = "opensearch"
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
  description = "Account that owns the domain; builds the access policy resource ARN."
  type        = string
}

variable "region_name" {
  description = "AWS region of the provider."
  type        = string
  default     = "eu-central-1"
}

variable "kms_key_arn" {
  description = "Key for encryption at rest."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per AZ; the domain is VPC-only."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) == 3
    error_message = "subnet_ids must list one subnet in each of three AZs."
  }
}

variable "security_group_ids" {
  description = "Security groups of the domain endpoint."
  type        = list(string)
}

variable "engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "OpenSearch_2.17"
}

variable "master_instance_type" {
  description = "Instance type of the three dedicated masters."
  type        = string
  default     = "m7g.large.search"
}

variable "data_instance_type" {
  description = "Instance type of the data nodes."
  type        = string
  default     = "r7g.xlarge.search"
}

variable "data_node_count" {
  description = "Data nodes; a multiple of three keeps the AZs even."
  type        = number
  default     = 6

  validation {
    condition     = var.data_node_count % 3 == 0
    error_message = "data_node_count must be a multiple of 3."
  }
}

variable "warm_instance_type" {
  description = "UltraWarm node type for data older than 30 days."
  type        = string
  default     = "ultrawarm1.medium.search"
}

variable "warm_node_count" {
  description = "UltraWarm nodes."
  type        = number
  default     = 2
}

variable "volume_size_gb" {
  description = "gp3 volume per data node."
  type        = number
  default     = 1024
}

variable "master_user_arn" {
  description = "IAM role that is the fine-grained access master; no internal user database exists."
  type        = string
}

variable "access_principal_arns" {
  description = "IAM principals that may call the domain endpoint."
  type        = list(string)
}

variable "log_group_arn" {
  description = "CloudWatch log group of application and slow logs."
  type        = string
}

variable "snapshot_bucket_arn" {
  description = "Bucket of the Snapshot Management repository, created by s3-backup."
  type        = string
}

variable "snapshot_prefix" {
  description = "Prefix of the snapshot repository."
  type        = string
  default     = "backups/opensearch"
}

variable "snapshot_kms_key_arn" {
  description = "Key of the snapshot bucket."
  type        = string
}
