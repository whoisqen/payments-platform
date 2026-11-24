variable "env" {
  description = "Environment segment of the resource name."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env must be dev, stage or prod."
  }
}

variable "region" {
  description = "AWS region of the provider; the unseal key and the secrets live here."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-central-1."
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

variable "account_id" {
  description = "AWS account of the environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
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
}

variable "cluster_name" {
  description = "EKS cluster of the Vault cell; its Pod Identity agent hands the roles to the pods."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to every role."
  type        = string
}

variable "snapshot_bucket_arn" {
  description = "Bucket of the s3-backup module (component vault-snapshots) in this region; the Raft snapshots go to the raft/ prefix."
  type        = string
}

variable "snapshot_kms_key_arn" {
  description = "Key that encrypts the snapshot bucket in this region."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "Key that encrypts the Secrets Manager secrets the bootstrap Job creates."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of Vault."
  type        = string
  default     = "vault"
}

variable "server_service_account" {
  description = "Service account of the Vault server pods (awskms seal)."
  type        = string
  default     = "vault"
}

variable "snapshot_service_account" {
  description = "Service account of the Raft snapshot CronJob."
  type        = string
  default     = "vault-snapshot"
}

variable "bootstrap_service_account" {
  description = "Service account of the init and unseal bootstrap Job."
  type        = string
  default     = "vault-bootstrap"
}

variable "snapshot_prefix" {
  description = "Key prefix of the Raft snapshots in the bucket."
  type        = string
  default     = "raft/"

  validation {
    condition     = endswith(var.snapshot_prefix, "/")
    error_message = "snapshot_prefix must end with a slash."
  }
}
