terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }

  # Bootstrap state is kept locally: the bucket it creates does not exist yet.
  # See README.md for optionally migrating this state into the bucket afterwards.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.project_name
        ManagedBy = "Terraform"
        Component = "bootstrap"
      },
      var.tags
    )
  }
}
