# -----------------------------------------------------------------------------
# GitHub Actions OIDC provider (one per AWS account)
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  github_repo_sub  = coalesce(var.github_oidc_subject_prefix, "repo:${var.github_repository}")

  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_host}"
  )

  # One plan and one apply role per environment, e.g. wp-platform-github-dev-plan.
  ci_roles = {
    for pair in setproduct(var.environments, ["plan", "apply"]) :
    "${pair[0]}-${pair[1]}" => { environment = pair[0], kind = pair[1] }
  }

  ci_role_name_prefix = "${var.project_name}-github-"

  # Folder that holds each environment's files, e.g. platform/dev/.
  state_env_prefix = { for env in var.environments : env => trim("${var.state_key_prefix}/${env}", "/") }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer validates these for GitHub, but older providers require the field.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# -----------------------------------------------------------------------------
# Trust policies
#
# plan:  pull requests and pushes to main (read-only, safe to run on any PR)
# apply: only jobs running in the GitHub environment named after the env
#        (add required reviewers to the "prod" environment in GitHub)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_trust" {
  for_each = local.ci_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values = (
        each.value.kind == "plan"
        ? [
          "${local.github_repo_sub}:pull_request",
          "${local.github_repo_sub}:ref:refs/heads/${var.github_default_branch}"
        ]
        : ["${local.github_repo_sub}:environment:${each.value.environment}"]
      )
    }
  }
}

resource "aws_iam_role" "ci" {
  for_each = local.ci_roles

  name                 = "${local.ci_role_name_prefix}${each.key}"
  description          = "GitHub Actions ${each.value.kind} role for ${var.github_repository} (${each.value.environment})"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust[each.key].json
  max_session_duration = 3600

  tags = {
    Environment = each.value.environment
  }
}

# -----------------------------------------------------------------------------
# Permissions: infrastructure
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  for_each = { for k, v in local.ci_roles : k => v if v.kind == "plan" }

  role       = aws_iam_role.ci[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "apply" {
  # Each apply role gets only its own environment's list, e.g. dev-apply|<arn>.
  for_each = merge([
    for env, arns in var.apply_role_policy_arns : {
      for arn in arns : "${env}-apply|${arn}" => { role = "${env}-apply", policy_arn = arn }
    }
  ]...)

  role       = aws_iam_role.ci[each.value.role].name
  policy_arn = each.value.policy_arn
}

# -----------------------------------------------------------------------------
# Permissions: state bucket, scoped to s3://<bucket>/<state_key_prefix>/<env>/
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_state" {
  for_each = local.ci_roles

  # Unconditional so a missing state object returns 404 (not 403) on first init.
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadOwnEnvironment"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/${local.state_env_prefix[each.value.environment]}/*"]
  }

  # Plan only writes the lock file; apply writes state and lock file.
  statement {
    sid     = "WriteOwnEnvironment"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = (
      each.value.kind == "plan"
      ? ["${aws_s3_bucket.state.arn}/${local.state_env_prefix[each.value.environment]}/*.tflock"]
      : ["${aws_s3_bucket.state.arn}/${local.state_env_prefix[each.value.environment]}/*"]
    )
  }

  # SSE-KMS: reading state needs Decrypt, writing state or the lock file needs GenerateDataKey.
  # ReadOnlyAccess (plan roles) doesn't include these.
  statement {
    sid       = "UseStateKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }
  }

  # ReadOnlyAccess / admin policies would otherwise reach other environments' state.
  dynamic "statement" {
    for_each = length(var.environments) > 1 ? [1] : []

    content {
      sid     = "DenyOtherEnvironments"
      effect  = "Deny"
      actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = [
        for env in var.environments :
        "${aws_s3_bucket.state.arn}/${local.state_env_prefix[env]}/*" if env != each.value.environment
      ]
    }
  }

  statement {
    sid       = "DenyBootstrapState"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/bootstrap/*"]
  }
}

resource "aws_iam_role_policy" "ci_state" {
  for_each = local.ci_roles

  name   = "terraform-state"
  role   = aws_iam_role.ci[each.key].id
  policy = data.aws_iam_policy_document.ci_state[each.key].json
}

# -----------------------------------------------------------------------------
# Guardrails: CI roles must not be able to modify the bootstrap itself
# (their own trust policies, the OIDC provider, or the state bucket config).
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_guardrails" {
  statement {
    sid    = "DenyChangingCiRoles"
    effect = "Deny"
    not_actions = [
      "iam:Get*",
      "iam:List*"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.ci_role_name_prefix}*",
      local.oidc_provider_arn
    ]
  }

  statement {
    sid    = "DenyChangingStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutLifecycleConfiguration",
      "s3:DeleteObjectVersion"
    ]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*"
    ]
  }

  # Apply roles have admin, which would otherwise let them disable or delete the state key.
  statement {
    sid    = "DenyChangingStateKey"
    effect = "Deny"
    not_actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*"
    ]
    resources = [
      aws_kms_key.state.arn,
      aws_kms_alias.state.arn
    ]
  }
}

resource "aws_iam_role_policy" "ci_guardrails" {
  for_each = local.ci_roles

  name   = "bootstrap-guardrails"
  role   = aws_iam_role.ci[each.key].id
  policy = data.aws_iam_policy_document.ci_guardrails.json
}

# -----------------------------------------------------------------------------
# Tag-scoped apply policy (e.g. dev)
#
# "May only touch things tagged Environment=<env>". No services or actions are
# listed, so new taggable resource types in the platform need no change here.
# The platform's default_tags put the Environment tag on every resource.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "tag_scoped_apply" {
  for_each = var.tag_scoped_apply_environments

  # Creating: the new resource must carry this environment's tag.
  statement {
    sid       = "AllowCreateWithEnvironmentTag"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  # Changing or deleting: the resource must already carry the tag.
  statement {
    sid       = "AllowManageEnvironmentResources"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # --- Things AWS can't tag, allowed by name ---------------------------------

  statement {
    sid       = "AllowEnvironmentKmsAliases"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/${each.value.name_prefix}-*"]
  }

  # SSM parameters can't be tagged in the same call that overwrites them.
  statement {
    sid = "AllowEnvironmentSsmParameters"
    actions = [
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:DeleteParameters",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${each.value.ssm_path}/*"]
  }

  statement {
    sid       = "AllowEnvironmentDnsRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = each.value.dns_names
    }
  }

  # --- Denies (always win over the allows above) ------------------------------

  # Nothing tagged for another environment, e.g. no dev subnet in the prod VPC.
  statement {
    sid       = "DenyOtherEnvironmentsResources"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [for env in var.environments : env if env != each.key]
    }
  }

  # The Environment tag can't be set to another value or removed.
  statement {
    sid       = "DenyOtherEnvironmentTag"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Environment"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  # Existing untagged EC2 resources (like the default VPC) can't be claimed by
  # tagging them: tags are only allowed while creating, or on own resources.
  statement {
    sid       = "DenyClaimingEc2Resources"
    effect    = "Deny"
    actions   = ["ec2:CreateTags"]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "ec2:CreateAction"
      values   = ["true"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # Without this the role could create a role tagged for its environment,
  # give it admin and switch to it. Also blocks assuming other roles.
  statement {
    sid         = "DenyIamChanges"
    effect      = "Deny"
    not_actions = ["iam:Get*", "iam:List*"]
    resources   = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_policy" "tag_scoped_apply" {
  for_each = var.tag_scoped_apply_environments

  name        = "${local.ci_role_name_prefix}${each.key}-tag-scoped-apply"
  description = "Allows changes only to resources tagged Environment=${each.key}"
  policy      = data.aws_iam_policy_document.tag_scoped_apply[each.key].json
}

# Attached by code because the policy's ARN doesn't exist until it is created.
# Pair it with ReadOnlyAccess in apply_role_policy_arns: the policy only covers changes.
resource "aws_iam_role_policy_attachment" "tag_scoped_apply" {
  for_each = var.tag_scoped_apply_environments

  role       = aws_iam_role.ci["${each.key}-apply"].name
  policy_arn = aws_iam_policy.tag_scoped_apply[each.key].arn
}
