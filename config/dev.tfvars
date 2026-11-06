environment = "dev"
aws_region  = "eu-central-1"

# Network: /24 subnets, single NAT gateway to keep costs down
vpc_cidr           = "10.10.0.0/16"
az_count           = 2
subnet_newbits     = 8
single_nat_gateway = true

# DNS: existing shared zone; dev gets its own record and certificate
hosted_zone_name = "vilina.c-loud.am"
domain_name      = "dev.vilina.c-loud.am"

kms_deletion_window_in_days = 7
