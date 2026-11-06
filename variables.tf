# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name. Used as the prefix of every resource name, e.g. dev-wp-vpc."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "aws_region" {
  description = "AWS region where the platform is created. Set per environment in config/<env>.tfvars."
  type        = string
}

variable "project_name" {
  description = "Short project name used in resource names (<environment>-<project_name>-<resource>)."
  type        = string
  default     = "wp"
}

variable "tags" {
  description = "Additional tags applied to all AWS resources through the provider."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block of the environment's VPC. Must not overlap with other environments."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to spread public and private subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 (ALB and RDS Multi-AZ need two AZs)."
  }
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix for each subnet: 8 turns a /16 into /24 subnets, 4 into /20."
  type        = number
}

variable "single_nat_gateway" {
  description = "true: one NAT gateway shared by all private subnets (cheaper). false: one NAT gateway per AZ (survives an AZ outage)."
  type        = bool
}

# -----------------------------------------------------------------------------
# DNS and certificates
# -----------------------------------------------------------------------------

variable "hosted_zone_name" {
  description = "Name of the existing Route 53 public hosted zone shared by all environments. It is looked up, never created or destroyed."
  type        = string
}

variable "domain_name" {
  description = "Domain the environment's ACM certificate is issued for, e.g. dev.example.com or example.com."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional names on the certificate, e.g. [\"www.example.com\"]."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

variable "kms_deletion_window_in_days" {
  description = "Waiting period before a scheduled KMS key deletion takes effect (7-30 days)."
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# SSM exports
# -----------------------------------------------------------------------------

variable "ssm_parameter_prefix" {
  description = "Root path for exported identifiers. Parameters are written under <prefix>/<environment>/..."
  type        = string
  default     = "/platform"
}
