data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Every resource name starts with this, e.g. dev-wp-vpc, prod-wp-rds-kms.
  name_prefix = "${var.environment}-${var.project_name}"

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Public subnets take the lower half of the VPC range, private subnets the
  # upper half, so either tier can grow without renumbering the other.
  # dev  (10.10.0.0/16, newbits 8): public 10.10.0.0/24...,  private 10.10.128.0/24...
  # prod (10.20.0.0/16, newbits 4): public 10.20.0.0/20...,  private 10.20.128.0/20...
  private_subnet_offset = pow(2, var.subnet_newbits - 1)

  public_subnet_cidrs = [
    for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, var.subnet_newbits, i)
  ]

  private_subnet_cidrs = [
    for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, var.subnet_newbits, local.private_subnet_offset + i)
  ]

  nat_gateway_count = var.single_nat_gateway ? 1 : var.az_count
}
