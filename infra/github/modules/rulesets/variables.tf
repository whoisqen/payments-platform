variable "repository" {
  type = string
}

variable "required_checks" {
  type = list(string)
}

variable "approvals" {
  type = number
}

variable "tagging_app_id" {
  description = "Id of the GitHub App that runs the tagging workflow; the only actor allowed to create v* tags."
  type        = number
}
