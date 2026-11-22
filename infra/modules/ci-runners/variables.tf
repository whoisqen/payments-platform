variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name of the CI account, for example the project short name."
}

variable "account_id" {
  type        = string
  description = "Account that hosts the runner cluster; part of the cache bucket name and of the runner role ARNs."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account id."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Permissions boundary attached to every role of the module."
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider of the runner cluster (output of the eks module); trust of the runner and External Secrets roles."
}

variable "oidc_issuer" {
  type        = string
  description = "Issuer host of the runner cluster OIDC provider, without https://."
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "GitHub Actions OIDC provider of the account; trust of the ECR push role."
}

variable "github_repository" {
  type        = string
  description = "Repository allowed to assume the push role, as owner/name."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "github_push_refs" {
  type        = list(string)
  description = "Git refs that may push images; the push role trusts only these."
  default     = ["refs/heads/main", "refs/heads/release/*"]
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repositories the runners pull from and the push role writes to."
}

variable "plan_role_arns" {
  type        = list(string)
  description = "Plan roles of the environment accounts that the ci-prod runner may assume; apply roles are never listed."
}

variable "cache_expiration_days" {
  type        = number
  description = "Days after which a build cache object expires."
  default     = 14
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Recovery window of the GitHub App key secrets after deletion."
  default     = 30
}

variable "external_secrets_namespace" {
  type        = string
  description = "Namespace of the External Secrets controller that reads the GitHub App keys."
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  type        = string
  description = "Service account of the External Secrets controller."
  default     = "external-secrets"
}

variable "tags" {
  type        = map(string)
  description = "Tags of every resource."
}
