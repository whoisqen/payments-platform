variable "name_prefix" {
  type        = string
  description = "Prefix of the secret names; set from config/platform.yaml (naming.prefix). The same prefix as the okta-sso secrets."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  default     = "shared-services"
  description = "Environment segment of the secret names; the central cluster runs in the shared-services account."

  validation {
    condition     = var.environment == "shared-services"
    error_message = "the central cluster belongs to the shared-services account."
  }
}

variable "region" {
  type        = string
  description = "Region of the cluster and of the secrets."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-central-1."
  }
}

variable "account_id" {
  type        = string
  description = "AWS account of the central cluster; builds the secret ARN pattern and the source account condition."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "cluster_name" {
  type        = string
  description = "Central cluster (eks module); the pod identity association is created in it."
}

variable "cluster_arn" {
  type        = string
  description = "Central cluster ARN; the trust policy accepts only pods of this cluster."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy (workload-boundary) attached to the role."
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed key of the secrets (the shared key of the kms stack): encrypts the secrets, and the role may decrypt with it only through Secrets Manager."
}

variable "namespace" {
  type        = string
  default     = "external-secrets"
  description = "Namespace of External Secrets Operator (deploy/platform/external-secrets)."
}

variable "service_account" {
  type        = string
  default     = "external-secrets"
  description = "Service account of External Secrets Operator (deploy/platform/external-secrets, serviceAccount.name)."
}

variable "generated_secrets" {
  type        = set(string)
  default     = []
  description = "Names of secrets (for example sentry/redis-password) whose first value Terraform generates with random_password instead of the owner entering it. Off by default: a generated value is also in the state, which is KMS-encrypted. Later changes of the value in Secrets Manager are ignored."

  validation {
    condition = alltrue([for n in var.generated_secrets : contains([
      "grafana/admin",
      "sentry/admin-password",
      "sentry/clickhouse-password",
      "sentry/launchpad-rpc-secret",
      "sentry/postgres-password",
      "sentry/postgres-replication-password",
      "sentry/redis-password",
      "sentry/system-secret-key",
    ], n)])
    error_message = "only grafana/admin and the sentry passwords and keys can be generated; webhook URLs, the database endpoint and the TLS material come from the owner."
  }
}

variable "secret_recovery_window_days" {
  type        = number
  default     = 30
  description = "Days a deleted secret stays recoverable."
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
