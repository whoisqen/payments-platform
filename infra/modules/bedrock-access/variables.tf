variable "name_prefix" {
  type        = string
  description = "Prefix of the resource names; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "account_id" {
  type        = string
  description = "Account that hosts the roles and the endpoint (shared-services)."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "region" {
  type        = string
  description = "Region of the Bedrock runtime endpoint and of the inference profile (config/ai-review.yaml model.region). EU only."

  validation {
    condition     = can(regex("^eu-", var.region))
    error_message = "region must be an EU region (data residency)."
  }
}

variable "inference_profile_id" {
  type        = string
  description = "Inference profile id the review calls (config/ai-review.yaml model.id), for example eu.<provider>.<model>-v1:0."

  validation {
    condition     = can(regex("^eu\\.[A-Za-z0-9.:_-]+$", var.inference_profile_id)) && !strcontains(var.inference_profile_id, "*")
    error_message = "inference_profile_id must be a concrete EU geo profile id (eu.<provider>.<model>) without wildcards; data residency."
  }
}

variable "profile_regions" {
  type        = list(string)
  description = "Regions the inference profile routes to; each one gets a foundation-model ARN in the review policy."

  validation {
    condition     = length(var.profile_regions) > 0 && alltrue([for r in var.profile_regions : can(regex("^eu(-[a-z]+)+-[0-9]$", r))])
    error_message = "profile_regions must list concrete EU regions (eu-*); data residency."
  }
}

variable "review_role_name" {
  type        = string
  description = "Name of the CI review role (config/platform.yaml ai.review_role_name)."
}

variable "github_repository" {
  type        = string
  description = "Repository in the form owner/name whose pull requests may assume the review role."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "ARN of the GitHub OIDC provider of the account (created by ci-oidc-roles)."
}

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "Permissions boundary of both roles; null for none."
}

variable "review_github_environment" {
  type        = string
  default     = "ai-review"
  description = "GitHub environment the review job runs in; the OIDC subject is repo:<owner>/<name>:environment:<this>. Protection rules of the environment are part of the gate."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.review_github_environment))
    error_message = "review_github_environment must be a plain environment name."
  }
}

variable "admin_principal_arns" {
  type        = list(string)
  default     = []
  description = "IAM Identity Center roles that may assume the admin-agent role, as ARN patterns arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/[<region>/|*/]AWSReservedSSO_<PermissionSet>_<suffix or *>. Plain roles and users are rejected. Empty creates no admin role."

  validation {
    condition = alltrue([
      for a in var.admin_principal_arns :
      can(regex("^arn:aws:iam::[0-9]{12}:role/aws-reserved/sso\\.amazonaws\\.com/((\\*|[a-z]{2}(-[a-z]+)+-[0-9])/)?AWSReservedSSO_[A-Za-z0-9+=,.@_-]+_(\\*|[0-9a-f]{16})$", a))
    ])
    error_message = "admin_principal_arns must be IAM Identity Center role patterns (role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_<PermissionSet>_*); a bare role/* is rejected."
  }

  validation {
    condition     = alltrue([for a in var.admin_principal_arns : startswith(a, "arn:aws:iam::${var.account_id}:")])
    error_message = "admin_principal_arns must belong to account_id (the Identity Center roles of this account)."
  }
}

variable "admin_require_mfa" {
  type        = bool
  default     = false
  description = "Require aws:MultiFactorAuthPresent on the assume-role call of the admin role. Leave false for Identity Center: its sessions do not carry the key (MFA happens at the IdP, Okta, and is enforced there), so true would lock everyone out. Set true only for principals that authenticate with an IAM MFA device."
}

variable "admin_principal_tag" {
  type = object({
    key   = string
    value = string
  })
  default     = null
  description = "Tag the caller's principal must carry (aws:PrincipalTag/<key>), for example a group attribute the IdP passes as a session tag; null for none."
}

variable "admin_allowed_model_arns" {
  type        = list(string)
  default     = []
  description = "Model ARNs (foundation models and inference profiles) the admin agent may invoke, EU regions only. The admin picks the model, so the list is data; no wildcard."

  validation {
    condition     = alltrue([for a in var.admin_allowed_model_arns : can(regex("^arn:aws:bedrock:eu-[a-z0-9-]+:", a)) && !strcontains(a, "*")])
    error_message = "admin_allowed_model_arns must be concrete Bedrock ARNs in EU regions without wildcards."
  }
}

variable "admin_log_group_names" {
  type        = list(string)
  default     = []
  description = "CloudWatch log groups of the account the admin agent may query (names, not ARNs)."

  validation {
    condition     = alltrue([for n in var.admin_log_group_names : !strcontains(n, "*")])
    error_message = "admin_log_group_names must be concrete names."
  }
}

variable "cde_account_ids" {
  type        = list(string)
  description = "Accounts of the cardholder data environment (required, not empty); their log groups, metrics and OAM links are denied to the admin role unless cde_logs_allowed. IAM cannot scope GetMetricData or oam:* by account reliably: those two denies match aws:ResourceAccount only where the service sets it, so they are a backstop. The control is to create no OAM link or sink policy that exposes CDE accounts to shared-services."

  validation {
    condition     = length(var.cde_account_ids) > 0 && alltrue([for a in var.cde_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "cde_account_ids must list at least one 12-digit account id."
  }
}

variable "cde_logs_allowed" {
  type        = bool
  default     = false
  description = "Lift the explicit deny on the log groups of the CDE accounts for the admin role. Needs a PCI review."
}

variable "vpc_id" {
  type        = string
  description = "VPC of the bedrock-runtime interface endpoint."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets of the endpoint, one per Availability Zone."

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must not be empty."
  }
}

variable "endpoint_allowed_cidrs" {
  type        = list(string)
  description = "CIDRs that may reach the endpoint on 443; nothing else is allowed in."

  validation {
    condition     = length(var.endpoint_allowed_cidrs) > 0 && alltrue([for c in var.endpoint_allowed_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "endpoint_allowed_cidrs must be valid CIDRs and never 0.0.0.0/0."
  }
}

variable "invocation_logging_enabled" {
  type        = bool
  default     = false
  description = "Deliver model invocation logs (prompt bodies included) to an encrypted S3 bucket. Off by default: sanitized prompts are still sensitive."
}

variable "invocation_log_retention_days" {
  type        = number
  default     = 30
  description = "Days the invocation log objects are kept."

  validation {
    condition     = var.invocation_log_retention_days >= 1 && var.invocation_log_retention_days <= 30
    error_message = "retention is 1 to 30 days."
  }
}

variable "invocation_log_audit_role_arn" {
  type        = string
  default     = null
  description = "ARN pattern of the only principal that may read invocation log objects (s3:GetObject); every other principal is denied by the bucket policy. Required when invocation_logging_enabled."
}

variable "invocation_log_access_log_bucket" {
  type        = string
  default     = null
  description = "Existing bucket that receives the server access logs of the invocation log bucket. Required when invocation_logging_enabled."
}

variable "invocation_log_object_lock" {
  type = object({
    mode = string
    days = number
  })
  default     = null
  description = "Object Lock default retention of the invocation log bucket (mode GOVERNANCE or COMPLIANCE); null for no lock. COMPLIANCE cannot be shortened or removed by anyone, including root."

  validation {
    condition     = var.invocation_log_object_lock == null ? true : (contains(["GOVERNANCE", "COMPLIANCE"], var.invocation_log_object_lock.mode) && var.invocation_log_object_lock.days >= 1)
    error_message = "invocation_log_object_lock needs mode GOVERNANCE or COMPLIANCE and days >= 1."
  }
}

variable "budget_monthly_usd" {
  type        = number
  default     = 200
  description = "Monthly Bedrock budget in USD; notifications at 80 percent actual and 100 percent forecast."

  validation {
    condition     = var.budget_monthly_usd > 0
    error_message = "budget_monthly_usd must be positive."
  }
}

variable "budget_service_names" {
  type        = list(string)
  default     = ["Amazon Bedrock"]
  description = "Cost Explorer service names the budget counts. Third-party models on Bedrock may bill under their own names (for example \"<Model> (Amazon Bedrock Edition)\"): check Cost Explorer and add them."
}

variable "budget_subscriber_emails" {
  type        = list(string)
  default     = []
  description = "E-mail addresses notified by the budget; with budget_sns_topic_arns at least one recipient is required."

  validation {
    condition     = length(var.budget_subscriber_emails) + length(var.budget_sns_topic_arns) > 0
    error_message = "Give the budget at least one e-mail address or SNS topic."
  }
}

variable "budget_sns_topic_arns" {
  type        = list(string)
  default     = []
  description = "SNS topics notified by the budget."
}

variable "input_token_alarm_threshold" {
  type        = number
  default     = 5000000
  description = "Input tokens per hour and model above which the CloudWatch alarm fires. The metric has a ModelId dimension only; a per-role limit is not possible."
}

variable "alarm_sns_topic_arns" {
  type        = list(string)
  default     = []
  description = "SNS topics notified by the input-token alarms."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Key that encrypts the invocation log bucket; its key policy must allow bedrock.amazonaws.com. Required when invocation_logging_enabled."
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
