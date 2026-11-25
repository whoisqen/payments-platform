variable "organization" {
  type    = string
  default = "CHANGEME-org"
}

variable "repository" {
  type    = string
  default = "payments-platform"
}

variable "repository_description" {
  type    = string
  default = "Payment orchestrator based on Hyperswitch"
}

variable "visibility" {
  type    = string
  default = "private"

  validation {
    condition     = contains(["private", "public", "internal"], var.visibility)
    error_message = "visibility must be private, public or internal."
  }
}

variable "billing_email" {
  type    = string
  default = "CHANGEME@example.invalid"
}

variable "default_branch" {
  type    = string
  default = "main"
}

# Section 10 says squash-merge and section 27 says rebase without merge commits; the owner picks one.
variable "allow_squash_merge" {
  type    = bool
  default = true
}

variable "allow_rebase_merge" {
  type    = bool
  default = false
}

# ci-gate waits for every check job of ci.yml (spec-gate, security and the test stages included), so it is the one required check.
# The advisory AI review is never required.
variable "required_checks" {
  type    = list(string)
  default = ["ci-gate"]
}

variable "main_approvals" {
  type    = number
  default = 2
}

variable "allowed_actions" {
  description = "Allowlisted actions, each pinned by commit SHA."
  type        = list(string)
  default = [
    "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683",
    "hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd",
    "github/codeql-action/*@48ab28a6f5dbc2a99bf1e0131198dd8f1df78169",
  ]
}

variable "teams" {
  description = "Team slugs used by environments and CODEOWNERS."
  type = object({
    payments_core = string
    security      = string
    platform      = string
    sre           = string
  })
  default = {
    payments_core = "CHANGEME-payments-core"
    security      = "CHANGEME-security"
    platform      = "CHANGEME-platform"
    sre           = "CHANGEME-sre"
  }
}

variable "codeowners_commit" {
  type = object({
    author  = string
    email   = string
    message = string
  })
  default = {
    author  = "CHANGEME"
    email   = "CHANGEME@example.invalid"
    message = "chore(ci): regenerate CODEOWNERS from owners.yaml"
  }
}

variable "github_app_id" {
  type    = string
  default = "0"
}

variable "github_app_installation_id" {
  type    = string
  default = "0"
}

variable "github_app_pem" {
  description = "Private key of the GitHub App, from TF_VAR_github_app_pem."
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "github_token" {
  description = "Personal access token, from TF_VAR_github_token; when null the GitHub App is used."
  type        = string
  sensitive   = true
  default     = null
}

variable "account_type" {
  description = "organization or user: a user account has no organization settings, teams or merge queue. Null takes owner.github_account_type from config/platform.yaml."
  type        = string
  default     = null

  validation {
    condition     = var.account_type == null || contains(["organization", "user"], coalesce(var.account_type, "user"))
    error_message = "account_type must be organization or user."
  }
}

variable "tag_bypass" {
  description = "Actor allowed to create v* tags; RepositoryRole 5 is the admin role."
  type = object({
    actor_id   = number
    actor_type = string
  })
  default = {
    actor_id   = 0
    actor_type = "Integration"
  }
}

variable "import_existing" {
  description = "Adopt a repository that already exists instead of creating it."
  type        = bool
  default     = false
}

variable "require_signatures" {
  description = "Require signed commits on main; false until commit signing is set up."
  type        = bool
  default     = false
}
