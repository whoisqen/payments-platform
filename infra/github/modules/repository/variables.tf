variable "name" {
  type = string
}

variable "description" {
  type = string
}

variable "visibility" {
  type = string

  validation {
    condition     = contains(["private", "public", "internal"], var.visibility)
    error_message = "visibility must be private, public or internal."
  }
}

variable "allow_squash_merge" {
  type = bool
}

variable "allow_rebase_merge" {
  type = bool
}

variable "allowed_actions" {
  description = "Allowlisted actions, each pinned by commit SHA."
  type        = list(string)
}
