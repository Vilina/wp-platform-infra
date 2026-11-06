terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.70, < 7.0"
    }
  }

  # Partial configuration: bucket, key and region come from config/<env>.backend.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "Terraform"
        Repository  = "wp-platform-infra"
      },
      var.tags
    )
  }
}
