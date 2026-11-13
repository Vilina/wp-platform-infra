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

variable "state_kms_deletion_window_in_days" {
  description = "Days before a scheduled deletion of the state KMS key takes effect (7-30)."
  type        = number
  default     = 30
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

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Start of the OIDC `sub` claim GitHub sends for this repository. Null means repo:<github_repository>.
    Repos with immutable subjects send repo:<owner>@<owner_id>/<repo>@<repo_id>; check with
    `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (sub_claim_prefix).
  EOT
  type        = string
  default     = null
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
  description = "Managed policies attached to each environment's apply role, keyed by environment."
  type        = map(list(string))
  default = {
    dev  = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    prod = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  validation {
    condition     = alltrue([for env in keys(var.apply_role_policy_arns) : contains(var.environments, env)])
    error_message = "Every key in apply_role_policy_arns must be listed in environments."
  }
}

variable "tag_scoped_apply_environments" {
  description = <<-EOT
    Environments that get a "may only touch resources tagged Environment=<env>" policy,
    keyed by environment. The names cover things AWS can't tag:
      name_prefix: platform resource name prefix, e.g. dev-wp (KMS aliases)
      ssm_path:    SSM export path, e.g. /platform/dev
      dns_names:   Route 53 record names, e.g. dev.example.com, *.dev.example.com
  EOT
  type = map(object({
    name_prefix = string
    ssm_path    = string
    dns_names   = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for env in keys(var.tag_scoped_apply_environments) : contains(var.environments, env)])
    error_message = "Every key in tag_scoped_apply_environments must be listed in environments."
  }
}

variable "state_key_prefix" {
  description = "Prefix in front of each environment's folder in the state bucket (state key platform/<env>/terraform.tfstate). Empty string for <env>/."
  type        = string
  default     = "platform"
}
