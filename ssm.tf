# -----------------------------------------------------------------------------
# Dependency publishing: identifiers other repositories need, under
# /platform/<environment>/..., e.g. /platform/dev/vpc/id
# -----------------------------------------------------------------------------

locals {
  ssm_path = "${var.ssm_parameter_prefix}/${var.environment}"

  ssm_exports = {
    "vpc/id"              = { type = "String", value = aws_vpc.this.id }
    "vpc/cidr"            = { type = "String", value = aws_vpc.this.cidr_block }
    "subnets/public/ids"  = { type = "StringList", value = join(",", aws_subnet.public[*].id) }
    "subnets/private/ids" = { type = "StringList", value = join(",", aws_subnet.private[*].id) }
    "dns/zone-id"         = { type = "String", value = data.aws_route53_zone.this.zone_id }
    "dns/zone-name"       = { type = "String", value = data.aws_route53_zone.this.name }
    "dns/domain-name"     = { type = "String", value = var.domain_name }
    "acm/certificate-arn" = { type = "String", value = aws_acm_certificate_validation.this.certificate_arn }
    "kms/rds/arn"         = { type = "String", value = aws_kms_key.this["rds"].arn }
    "kms/efs/arn"         = { type = "String", value = aws_kms_key.this["efs"].arn }
    "kms/secrets/arn"     = { type = "String", value = aws_kms_key.this["secrets"].arn }
  }
}

resource "aws_ssm_parameter" "exports" {
  for_each = local.ssm_exports

  name  = "${local.ssm_path}/${each.key}"
  type  = each.value.type
  value = each.value.value

  tags = {
    Name = "${local.name_prefix}-${replace(each.key, "/", "-")}"
  }
}
