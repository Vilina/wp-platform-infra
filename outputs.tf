# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the environment's VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the environment's VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability Zones the subnets are spread across."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT gateways)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EC2 application instances, RDS, EFS)."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "Route table used by the public subnets."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Route tables used by the private subnets, one per AZ."
  value       = aws_route_table.private[*].id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs (one in dev, one per AZ in prod)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "Public IPs that private-subnet traffic leaves from. Useful for allow-lists."
  value       = aws_eip.nat[*].public_ip
}

# -----------------------------------------------------------------------------
# DNS and certificates
# -----------------------------------------------------------------------------

output "hosted_zone_id" {
  description = "ID of the shared Route 53 hosted zone."
  value       = data.aws_route53_zone.this.zone_id
}

output "acm_certificate_arn" {
  description = "ARN of the validated ACM certificate for the environment's domain."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

output "kms_key_arns" {
  description = "KMS key ARNs keyed by purpose: rds, efs, secrets."
  value       = { for k, key in aws_kms_key.this : k => key.arn }
}

output "kms_key_aliases" {
  description = "KMS key aliases keyed by purpose."
  value       = { for k, alias in aws_kms_alias.this : k => alias.name }
}

# -----------------------------------------------------------------------------
# SSM
# -----------------------------------------------------------------------------

output "ssm_parameter_names" {
  description = "SSM Parameter Store paths of all exported identifiers."
  value       = sort([for p in aws_ssm_parameter.exports : p.name])
}
