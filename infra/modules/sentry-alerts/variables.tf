variable "organization" {
  type        = string
  description = "Slug of the Sentry organization."
}

variable "slack_workspace_id" {
  type        = string
  description = "Integration id of the Slack workspace in Sentry (Settings, Integrations, Slack)."

  validation {
    condition     = length(trimspace(var.slack_workspace_id)) > 0
    error_message = "slack_workspace_id must not be empty."
  }
}

variable "slack_channel" {
  type        = string
  description = "Slack channel of the high and critical issues, for example #payments-sentry-critical."

  validation {
    condition     = can(regex("^#[a-z0-9._-]+$", var.slack_channel))
    error_message = "slack_channel must look like #channel-name."
  }
}

variable "projects" {
  type        = list(string)
  default     = null
  description = "Project slugs that get the rules; null takes every project of the organization at plan time."
}

variable "frequency_minutes" {
  type        = number
  default     = 30
  description = "Minimum minutes between two notifications of the same issue."
}
