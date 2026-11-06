# -----------------------------------------------------------------------------
# Customer managed KMS keys for RDS, EFS and Secrets Manager
#
# Every key gets the same policy shape:
#   1. The account (IAM) administers the key, so access is managed with IAM policies.
#   2. Principals in this account can use the key only through its own service
#      (kms:ViaService), e.g. the RDS key can't be used directly or by EFS.
# -----------------------------------------------------------------------------

locals {
  kms_keys = {
    rds = {
      description = "RDS storage, snapshots and Performance Insights"
      service     = "rds"
    }
    efs = {
      description = "EFS file system for WordPress shared content"
      service     = "elasticfilesystem"
    }
    secrets = {
      description = "Secrets Manager secrets (database credentials, WordPress salts)"
      service     = "secretsmanager"
    }
  }
}

data "aws_iam_policy_document" "kms" {
  for_each = local.kms_keys

  statement {
    sid       = "EnableAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowUseThrough${title(each.value.service)}"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["${each.value.service}.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "this" {
  for_each = local.kms_keys

  description             = "${local.name_prefix}: ${each.value.description}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days
  policy                  = data.aws_iam_policy_document.kms[each.key].json

  tags = {
    Name = "${local.name_prefix}-${each.key}-kms"
  }
}

resource "aws_kms_alias" "this" {
  for_each = local.kms_keys

  name          = "alias/${local.name_prefix}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}
