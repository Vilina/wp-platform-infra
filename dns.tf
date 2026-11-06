# -----------------------------------------------------------------------------
# Route 53 hosted zone (existing, shared by dev and prod)
#
# Looked up, not imported: if both environment states imported the zone, each
# would own it and destroying one environment would try to delete it.
# Each environment only adds its own records (certificate validation here,
# ALB alias records in the application repo).
# -----------------------------------------------------------------------------

data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}

# -----------------------------------------------------------------------------
# ACM certificate for the environment's domain (same region as the ALB)
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = {
    Name = "${local.name_prefix}-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
