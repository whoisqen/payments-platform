variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "account_id" {
  type        = string
  description = "Account that hosts the runners; part of the cache bucket name and of the role ARNs."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account id."
  }
}

variable "region" {
  type        = string
  description = "Region of the runner pools."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Permissions boundary attached to every role of the module."
}

variable "vpc_id" {
  type        = string
  description = "VPC of the runner pools; each pool gets a security group with outbound HTTPS only and no inbound rule."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets of the trusted pools, one per Availability Zone."
}

variable "untrusted_subnet_ids" {
  type        = list(string)
  default     = null
  description = "Subnets of the untrusted pool; give it subnets without routes to other networks so that pull request code cannot reach them. null uses subnet_ids."
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "Customer managed key that encrypts the root volume of every runner."
}

variable "ami_ssm_parameter" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  description = "SSM parameter that names the arm64 image of the runners; the pools replace their instances when it changes."
}

variable "runner_version" {
  type        = string
  description = "Version of the GitHub Actions runner that an instance installs at boot (without the v), pinned so that a new release is a reviewed change."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version))
    error_message = "runner_version must look like 2.329.0."
  }
}

variable "runner_sha256" {
  type        = string
  description = "SHA-256 of the linux arm64 runner archive of runner_version; the instance refuses an archive that does not match."

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.runner_sha256)) && var.runner_sha256 != join("", [for i in range(64) : "0"])
    error_message = "runner_sha256 must be the 64 hex characters of the release checksum, not the placeholder of zeros."
  }
}

variable "pools" {
  type = map(object({
    instance_types = list(string)
    min_size       = number
    warm_size      = number
    max_size       = number
    root_volume_gb = number
    on_demand_base = number
    target_cpu     = number
    labels         = list(string)
    cache_write    = bool
    ecr_pull       = bool
    assume_plan    = bool
    untrusted      = bool
  }))
  description = "Runner pools, one Auto Scaling group each; the key is the runner label that jobs use in runs-on. Instance types are alternatives for Spot capacity, warm_size is the minimum during working hours and target_cpu the average CPU that adds instances."

  validation {
    condition     = length(var.pools) > 0 && alltrue([for k in keys(var.pools) : can(regex("^[a-z][a-z0-9-]{1,30}$", k))])
    error_message = "pools needs at least one lower-case name."
  }
  validation {
    condition     = alltrue([for p in values(var.pools) : p.min_size >= 0 && p.min_size <= p.warm_size && p.warm_size <= p.max_size && p.max_size >= 1 && length(p.instance_types) > 0])
    error_message = "each pool needs min_size <= warm_size <= max_size, max_size >= 1 and at least one instance type."
  }
  validation {
    condition     = alltrue([for p in values(var.pools) : p.target_cpu >= 20 && p.target_cpu <= 80])
    error_message = "target_cpu must be between 20 and 80."
  }
  validation {
    condition     = alltrue([for p in values(var.pools) : !(p.untrusted && (p.cache_write || p.ecr_pull || p.assume_plan))])
    error_message = "an untrusted pool may not write the cache, pull images or assume a role."
  }
}

variable "work_start_cron" {
  type        = string
  default     = "0 7 * * 1-5"
  description = "Cron expression at which pools rise to warm_size."
}

variable "work_end_cron" {
  type        = string
  default     = "0 19 * * 1-5"
  description = "Cron expression at which pools return to min_size."
}

variable "time_zone" {
  type        = string
  default     = "Etc/UTC"
  description = "Time zone of the working hours."
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "GitHub Actions OIDC provider of the account; trust of the ECR push role."
}

variable "github_repository" {
  type        = string
  description = "Repository that the runners serve and that may assume the push role, as owner/name."

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

variable "pull_through_cache_prefixes" {
  type        = list(string)
  default     = []
  description = "ECR pull-through cache prefixes that pools with ecr_pull may import into on a first pull; empty grants nothing."
}

variable "plan_role_arns" {
  type        = list(string)
  description = "Plan roles of the environment accounts that pools with assume_plan may assume; apply roles are never listed."
}

variable "cache_expiration_days" {
  type        = number
  description = "Days after which a build cache object expires."
  default     = 14
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Recovery window of the GitHub App secrets after deletion."
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Tags of every resource."
}
