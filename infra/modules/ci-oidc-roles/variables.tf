variable "account_id" {
  type        = string
  description = "Account that hosts the roles."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "environment" {
  type        = string
  description = "dev, stage, prod or shared-services (the CI account); also the state key prefix."

  validation {
    condition     = contains(["dev", "stage", "prod", "shared-services"], var.environment)
    error_message = "environment must be dev, stage, prod or shared-services."
  }
}

variable "github_repository" {
  type        = string
  description = "Repository in the form owner/name that may assume the roles."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "Create the GitHub OIDC provider; false when the account already has it."
}

variable "oidc_provider_arn" {
  type        = string
  default     = null
  description = "ARN of an existing GitHub OIDC provider; used when create_oidc_provider is false."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy (policy/iam/boundaries) attached to every role and required on roles they create."
}

variable "state_bucket_arn" {
  type        = string
  description = "Terraform state bucket."
}

variable "state_kms_key_arn" {
  type        = string
  description = "KMS key of the state bucket."
}

variable "plan_read_actions" {
  type = list(string)
  default = [
    "ec2:Describe*", "elasticloadbalancing:Describe*", "kms:Describe*", "kms:Get*", "kms:List*",
    "iam:Get*", "iam:List*", "s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration",
    "s3:GetReplicationConfiguration", "s3:GetAccelerateConfiguration", "s3:ListAllMyBuckets",
    "ecr:Describe*", "ecr:GetLifecyclePolicy", "ecr:GetRepositoryPolicy", "ecr:GetRegistryScanningConfiguration",
    "ecr:GetReplicationConfiguration", "ecr:ListTagsForResource", "route53:Get*", "route53:List*",
    "acm:Describe*", "acm:List*", "globalaccelerator:Describe*", "globalaccelerator:List*",
    "network-firewall:Describe*", "network-firewall:List*", "ram:Get*", "ram:List*", "logs:Describe*",
    "dynamodb:Describe*", "rds:Describe*", "elasticache:Describe*", "memorydb:Describe*", "tag:GetResources",
  ]
  description = "Metadata reads of the plan role; no data reads (objects, secrets, parameters)."
}

variable "apply_roles" {
  type = map(object({
    github_environment = optional(string)
    actions            = list(string)
    resource_arns      = list(string)
    unscoped_actions   = optional(list(string), [])
  }))
  default     = {}
  description = "One apply role per component (key = component): actions on named resources (github_environment is no longer part of the trust and is ignored), and the few actions that cannot be scoped."

  validation {
    condition = alltrue([
      for r in var.apply_roles : !contains(r.actions, "*") && !contains(r.unscoped_actions, "*") &&
      alltrue([for a in concat(r.actions, r.unscoped_actions) : !contains(["iam:*", "organizations:*", "sts:*"], a)])
    ])
    error_message = "no role may hold *, iam:*, organizations:* or sts:*."
  }

  validation {
    condition     = alltrue([for r in var.apply_roles : length(r.resource_arns) > 0 && !contains(r.resource_arns, "*")])
    error_message = "resource_arns must name resources; use unscoped_actions for actions without resource-level scoping."
  }
}

variable "apply_refs" {
  type        = list(string)
  default     = ["refs/heads/main", "refs/heads/release/*"]
  description = "Git refs that may assume an apply role: main and release branches. The only wildcard allowed is the release/* suffix."

  validation {
    condition     = length(var.apply_refs) > 0 && alltrue([for r in var.apply_refs : can(regex("^refs/heads/(main|release/([A-Za-z0-9._-]+|[*]))$", r))])
    error_message = "apply_refs may only be refs/heads/main, refs/heads/release/<name> or refs/heads/release/*."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
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

variable "plan_refs" {
  type        = list(string)
  default     = ["refs/heads/main"]
  description = "Refs that may assume the plan role: refs/heads/main for the nightly drift check; pull requests never get state access."

  validation {
    condition     = length(var.plan_refs) > 0 && alltrue([for r in var.plan_refs : r == "refs/heads/main"])
    error_message = "plan_refs must hold refs/heads/main and nothing else."
  }
}

variable "ecr_read_repository_arns" {
  type        = list(string)
  default     = []
  description = "Repositories the ecr-read role may read; empty creates no ecr-read role."

  validation {
    condition     = alltrue([for a in var.ecr_read_repository_arns : startswith(a, "arn:aws:ecr:") && a != "*"])
    error_message = "ecr_read_repository_arns must be ECR repository ARNs."
  }
}

variable "ecr_read_refs" {
  type        = list(string)
  default     = ["refs/heads/main"]
  description = "Refs that may assume the ecr-read role: the schedule, repository_dispatch and dispatches of main run on refs/heads/main."

  validation {
    condition     = length(var.ecr_read_refs) > 0 && alltrue([for r in var.ecr_read_refs : can(regex("^refs/heads/(main|release/([A-Za-z0-9._-]+|[*]))$", r))])
    error_message = "ecr_read_refs may only be refs/heads/main, refs/heads/release/<name> or refs/heads/release/*."
  }
}
