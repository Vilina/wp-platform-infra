variable "aws_region" {
  description = "AWS region where the state bucket will be created."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix used for the default bucket name and tags."
  type        = string
  default     = "wp-platform"
}

variable "bucket_name" {
  description = "Explicit bucket name. Leave null to use <project_name>-tfstate-<account_id>-<region>."
  type        = string
  default     = null
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old versions of state, tfvars and config files before they are deleted."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags applied to all resources through the provider."
  type        = map(string)
  default     = {}
}

variable "environments" {
  description = "Environments that get their own GitHub Actions plan/apply roles and state prefix in the bucket."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as <owner>/<repo>."
  type        = string
  default     = "Vilina/wp-platform-infra"
}

variable "github_default_branch" {
  description = "Branch whose pushes may use the plan roles."
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if the account already has one for token.actions.githubusercontent.com."
  type        = bool
  default     = true
}

variable "apply_role_policy_arns" {
  description = "Managed policies attached to every apply role. Narrow this once the platform's resource types are known."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
