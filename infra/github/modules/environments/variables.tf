variable "repository" {
  type = string
}

variable "branch" {
  type = string
}

variable "teams" {
  description = "Team slugs."
  type = object({
    payments_core = string
    security      = string
    platform      = string
    sre           = string
  })
}
