terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    okta = {
      source  = "okta/okta"
      version = ">= 5.0, < 6.0"
    }
  }
}
