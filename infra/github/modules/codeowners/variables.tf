variable "organization" {
  type = string
}

variable "repository" {
  type = string
}

variable "branch" {
  type = string
}

variable "owners_file" {
  description = "Path to owners.yaml."
  type        = string
}

variable "teams" {
  type = object({
    payments_core = string
    security      = string
    platform      = string
    sre           = string
  })
}

variable "handles" {
  description = "Owner handle per team key that replaces @<organization>/<slug>; a personal account has no teams, so every team maps to the user."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for h in values(var.handles) : can(regex("^@[A-Za-z0-9][A-Za-z0-9-]*(/[A-Za-z0-9._-]+)?$", h))])
    error_message = "a handle looks like @user or @org/team."
  }
}

variable "commit" {
  type = object({
    author  = string
    email   = string
    message = string
  })
}
