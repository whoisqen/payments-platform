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

variable "commit" {
  type = object({
    author  = string
    email   = string
    message = string
  })
}
