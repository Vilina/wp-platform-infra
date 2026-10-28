# Bootstrap: CI access and Terraform state bucket

Creates everything the main project needs before its first `terraform init`:

1. The GitHub Actions OIDC provider and IAM roles for the **dev** and **prod** environments
2. The S3 bucket that holds Terraform state, per-environment `tfvars` and other environment config files

Dev and prod share one AWS account, so this runs **once**, with admin credentials, from a laptop.

## GitHub Actions OIDC roles

GitHub Actions gets short-lived AWS credentials through OIDC, so no AWS access keys are stored in GitHub.

| Role | Assumable by (`sub` claim) | AWS permissions | State access |
| --- | --- | --- | --- |
| `wp-platform-github-dev-plan` | pull requests, pushes to `main` | `ReadOnlyAccess` | read `dev/*`, write lock file |
| `wp-platform-github-dev-apply` | jobs with `environment: dev` | `apply_role_policy_arns` | read/write `dev/*` |
| `wp-platform-github-prod-plan` | pull requests, pushes to `main` | `ReadOnlyAccess` | read `prod/*`, write lock file |
| `wp-platform-github-prod-apply` | jobs with `environment: prod` | `apply_role_policy_arns` | read/write `prod/*` |

Every role also:

- is denied access to the other environment's state prefix and to `bootstrap/*`
- is denied changes to the `wp-platform-github-*` roles, the OIDC provider, and the state bucket's settings (policy, versioning, encryption, deleting object versions), so CI can't widen its own access or wipe state history

Apply roles default to `AdministratorAccess`. Because dev and prod share an account, the dev apply role can technically change prod resources. Only the state is separated. Narrow `apply_role_policy_arns` (or add a permissions boundary) once the platform's resource types are known.

If the account already has a `token.actions.githubusercontent.com` OIDC provider, set `create_oidc_provider = false`.

## State bucket

- S3 bucket, named `<project_name>-tfstate-<account_id>-<region>` by default
- Versioning (so you can recover any earlier state or tfvars file)
- SSE-S3 (AES256) default encryption
- Public access fully blocked, ACLs disabled (`BucketOwnerEnforced`)
- A bucket policy that denies non-HTTPS access
- A lifecycle rule that deletes old versions after `noncurrent_version_retention_days` (default 90)
- `prevent_destroy`, so `terraform destroy` can't delete the bucket by mistake

No DynamoDB table is needed: the main project locks state with an S3 lock file (`use_lockfile = true`).

## Suggested bucket layout

```text
s3://<bucket>/
├── bootstrap/terraform.tfstate   # optional, see "Migrating bootstrap state"
├── dev/
│   ├── terraform.tfstate
│   └── terraform.tfvars
└── prod/
    ├── terraform.tfstate
    └── terraform.tfvars
```

CI roles are scoped to their environment's prefix, so dev and prod files must live under `dev/` and `prod/`.

## Usage

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # optional, defaults work too
terraform init
terraform apply
terraform output
```

Then, in GitHub (**Settings → Environments**):

1. Create the environments `dev` and `prod`. Add required reviewers to `prod`.
2. In each environment, add secrets `AWS_PLAN_ROLE_ARN` and `AWS_APPLY_ROLE_ARN` from the `ci_role_arns` output.
3. Set repository secret `TF_STATE_BUCKET` to the `bucket_name` output.

Upload each environment's tfvars:

```bash
aws s3 cp dev.tfvars "s3://$(terraform output -raw bucket_name)/dev/terraform.tfvars"
```

Workflows must request `id-token: write`. Apply jobs must declare `environment: dev` or `environment: prod`, because the apply roles only trust that `sub` claim.

## Bootstrap state

The bucket doesn't exist until this runs, so bootstrap state starts out **local** (`bootstrap/terraform.tfstate`, which is git-ignored). Keep it, or move it into the bucket.

### Migrating bootstrap state (optional)

After the first apply, create `bootstrap/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket       = "<bucket_name output>"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

and run:

```bash
terraform init -migrate-state
```

Then delete the local `terraform.tfstate*` files.

## Deleting the bucket

Remove the `prevent_destroy` block first, then empty every object version and delete the bucket. Do this only after destroying all infrastructure whose state lives in it.
