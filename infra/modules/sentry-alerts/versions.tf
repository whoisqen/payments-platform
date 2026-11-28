terraform {
  required_version = ">= 1.9"

  required_providers {
    sentry = {
      source  = "jianyuan/sentry"
      version = ">= 0.17, < 1.0"
    }
  }
}
