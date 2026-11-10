output "bucket_name" {
  description = "Name of the state bucket. Use it as TF_STATE_BUCKET in CI and as `bucket` in backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket, for IAM policies of CI roles."
  value       = aws_s3_bucket.state.arn
}

output "bucket_region" {
  description = "Region of the state bucket."
  value       = aws_s3_bucket.state.region
}

output "state_kms_key_arn" {
  description = "ARN of the KMS key that encrypts state. Use it as `kms_key_id` in every backend config."
  value       = aws_kms_key.state.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = local.oidc_provider_arn
}

output "ci_role_arns" {
  description = "GitHub Actions role ARNs, keyed <env>-plan / <env>-apply. Store them as GitHub environment secrets."
  value       = { for k, r in aws_iam_role.ci : k => r.arn }
}
