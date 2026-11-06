environment = "prod"
aws_region  = "eu-central-1"

# Network: /20 subnets, one NAT gateway per AZ
vpc_cidr           = "10.20.0.0/16"
az_count           = 2
subnet_newbits     = 4
single_nat_gateway = false

# DNS: existing shared zone; prod gets its own record and certificate
hosted_zone_name = "vilina.c-loud.am"
domain_name      = "vilina.c-loud.am"

kms_deletion_window_in_days = 30
