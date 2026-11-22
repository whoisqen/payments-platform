terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Runs in the AFT management account; the backend is passed with -backend-config like the other stacks.
provider "aws" {
  region = "eu-central-1"
}
