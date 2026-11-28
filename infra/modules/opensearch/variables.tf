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
  description = "Component segment of the domain name; the whole name is limited to 28 characters."
  type        = string
  default     = "opensearch"
}

variable "domain_name" {
  description = "Domain name instead of <prefix>-<env>-<region-short>-<component>, for example central.opensearch.domain_name; 3-28 characters."
  type        = string
  default     = null
}

variable "custom_endpoint" {
  description = "Custom endpoint of the domain and Dashboards (central.opensearch.dashboards_host) with an ACM certificate issued by the private CA of shared-services (admin-edge ca_arn)."
  type = object({
    host                      = string
    certificate_authority_arn = string
  })
  default = null

  validation {
    condition     = var.custom_endpoint == null || can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.custom_endpoint.host))
    error_message = "custom_endpoint.host must be a lower-case DNS name."
  }
}

variable "saml" {
  description = "Dashboards sign-in through a SAML identity provider (Okta); null leaves Dashboards without SSO until the metadata exists."
  type = object({
    entity_id               = string
    metadata_content        = string
    master_backend_role     = string
    roles_key               = optional(string, "groups")
    session_timeout_minutes = optional(number, 60)
  })
  default = null
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

variable "vpc_id" {
  description = "VPC of the domain; the module creates the domain and client security groups in it."
  type        = string
}

variable "endpoint_account_ids" {
  description = "Accounts allowed to create an OpenSearch-managed VPC endpoint of the domain in their VPC, for example the admin agent path of dev, stage and prod."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.endpoint_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "endpoint_account_ids must be 12-digit account ids."
  }
}

variable "client_cidr_blocks" {
  description = "CIDRs admitted on 443, for example the environment VPCs whose admin agent reads its logs through the transit gateway."
  type        = list(string)
  default     = []
}

variable "client_security_group_ids" {
  description = "Security groups admitted on 443 besides the client group of the module, for example the node group of the central cluster."
  type        = list(string)
  default     = []
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
  description = "Data nodes; a multiple of availability_zone_count keeps the AZs even."
  type        = number
  default     = 6

  validation {
    condition     = var.data_node_count >= 1
    error_message = "data_node_count must be at least 1."
  }
}

variable "availability_zone_count" {
  description = "AZs of the data nodes: 3 in stage and prod, 1 in dev (one node, no zone awareness); the first subnets are used."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 2, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be 1, 2 or 3."
  }
}

variable "dedicated_master_count" {
  description = "Dedicated master nodes: 3, or 0 for a dev domain without them."
  type        = number
  default     = 3

  validation {
    condition     = contains([0, 3], var.dedicated_master_count)
    error_message = "dedicated_master_count must be 0 or 3."
  }
}

variable "warm_instance_type" {
  description = "UltraWarm node type for data older than 30 days."
  type        = string
  default     = "ultrawarm1.medium.search"
}

variable "warm_node_count" {
  description = "UltraWarm nodes; 0 disables the warm tier."
  type        = number
  default     = 2

  validation {
    condition     = var.warm_node_count == 0 || var.warm_node_count >= 2
    error_message = "warm_node_count must be 0 or at least 2."
  }
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
  description = "IAM principals the access policy admits; [\"*\"] with SAML, where fine-grained access control decides."
  type        = list(string)
}

variable "logs_kms_key_arn" {
  description = "Key of the application and slow log group; its policy must admit logs.amazonaws.com."
  type        = string
}

variable "log_retention_days" {
  description = "Days the error and slow logs stay in CloudWatch."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1
    error_message = "log_retention_days must be at least 1."
  }
}

variable "snapshot_bucket_arn" {
  description = "Bucket of the Snapshot Management repository; null creates no snapshot role (the service keeps its automated hourly snapshots)."
  type        = string
  default     = null
}

variable "snapshot_prefix" {
  description = "Prefix of the snapshot repository."
  type        = string
  default     = "backups/opensearch"
}

variable "snapshot_kms_key_arn" {
  description = "Key of the snapshot bucket; required with snapshot_bucket_arn."
  type        = string
  default     = null

  validation {
    condition     = var.snapshot_bucket_arn == null || var.snapshot_kms_key_arn != null
    error_message = "snapshot_kms_key_arn must be set with snapshot_bucket_arn."
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
