variable "repository" {
  type = string
}

variable "required_checks" {
  type = list(string)
}

variable "approvals" {
  type = number
}

variable "tag_bypass" {
  description = "Actor allowed to create v* tags."
  type = object({
    actor_id   = number
    actor_type = string
  })
}

variable "merge_queue" {
  description = "Merge queue exists only for repositories owned by an organization."
  type        = bool
}

variable "main_admin_bypass" {
  description = "Let repository admins merge a pull request without the review rules (single maintainer)."
  type        = bool
  default     = false
}

variable "require_signatures" {
  description = "Require signed commits on main; off until commit signing is set up."
  type        = bool
  default     = true
}
