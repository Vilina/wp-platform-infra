# WordPress Platform Infrastructure (Repository 1)

Foundational infrastructure shared by the WordPress application: networking, DNS certificates, and encryption keys. It changes rarely. The application layer (ALB, EC2 Auto Scaling, RDS, EFS) lives in the application repository and reads this repo's exports from SSM Parameter Store.

Each environment (`dev`, `prod`) is a separate deployment of the same code with its own variables and its own state.

## What it creates (per environment)

| Area | Resources | Names (dev example) |
| --- | --- | --- |
| VPC | VPC with an isolated CIDR range | `dev-wp-vpc` |
| Subnets | Public and private subnet in each AZ | `dev-wp-public-eu-central-1a`, `dev-wp-private-eu-central-1a` |
| Gateways | Internet Gateway; NAT Gateway(s) with Elastic IPs | `dev-wp-igw`, `dev-wp-nat-eu-central-1a` |
| Routing | Public route table (to IGW); one private route table per AZ (to NAT) | `dev-wp-public-rt`, `dev-wp-private-rt-eu-central-1a` |
| DNS / TLS | ACM certificate for the environment's domain, validated in the shared hosted zone | `dev-wp-cert` |
| KMS | Customer managed keys for RDS, EFS and Secrets Manager, with rotation | `alias/dev-wp-rds`, `alias/dev-wp-efs`, `alias/dev-wp-secrets` |
| Exports | SSM parameters under `/platform/<env>/...` | `/platform/dev/vpc/id` |

Every resource also carries `Environment`, `Project`, `ManagedBy` and `Repository` tags through the provider's `default_tags`.

### Environment differences

| Setting | dev | prod |
| --- | --- | --- |
| VPC CIDR | `10.10.0.0/16` | `10.20.0.0/16` |
| Subnet size | `/24` | `/20` |
| Public subnets | `10.10.0.0/24`, `10.10.1.0/24` | `10.20.0.0/20`, `10.20.16.0/20` |
| Private subnets | `10.10.128.0/24`, `10.10.129.0/24` | `10.20.128.0/20`, `10.20.144.0/20` |
| NAT Gateways | 1 (shared) | 1 per AZ |
| KMS deletion window | 7 days | 30 days |

Public subnets use the lower half of the VPC range and private subnets the upper half, so either tier can grow without renumbering the other. The VPCs are not peered, so there is no route between dev and prod.

## Project structure

```text
wp-platform-infra/
├── bootstrap/              # one-time: GitHub OIDC roles + S3 state bucket (see bootstrap/README.md)
├── config/
│   ├── dev.backend         # S3 backend settings for dev  (key platform/dev/terraform.tfstate)
│   ├── dev.tfvars          # dev variables
│   ├── prod.backend        # S3 backend settings for prod (key platform/prod/terraform.tfstate)
│   └── prod.tfvars         # prod variables
├── .github/workflows/      # CI: plan/apply and destroy
├── terraform.tf            # Terraform version, AWS provider, default tags, empty S3 backend
├── variables.tf            # Input variables
├── locals.tf               # Naming prefix, AZ list, subnet CIDR calculation, account lookups
├── network.tf              # VPC, subnets, IGW, NAT, route tables
├── dns.tf                  # Hosted zone lookup, ACM certificate + DNS validation
├── kms.tf                  # KMS keys, key policies, aliases
├── ssm.tf                  # SSM Parameter Store exports
└── outputs.tf              # Terraform outputs
```

## Route 53 hosted zone

The hosted zone already exists and is **shared** by dev and prod. It's looked up with a `data "aws_route53_zone"` source, never created, imported or destroyed. If both environment states imported it, each would own the zone, and destroying dev would try to delete it.

Each environment only adds its own records to the zone:

- this repo: ACM DNS validation records for the environment's `domain_name`
- application repo: the ALB alias record (`dev.<zone>` / `<zone>`), using the zone ID from `/platform/<env>/dns/zone-id`

Set `hosted_zone_name` and `domain_name` in `config/<env>.tfvars`.

## KMS key policies

All three keys share one policy shape:

1. **Account administration:** the account root principal has `kms:*`, so access is managed through IAM policies (standard AWS default).
2. **Service-only use:** principals in this account may encrypt, decrypt and create grants only when the request comes through the key's own service (`kms:ViaService` = `rds.<region>.amazonaws.com`, `elasticfilesystem...` or `secretsmanager...`). The RDS key can't be used directly or by EFS, for example.

Automatic yearly key rotation is enabled.

## Exports for other repositories

Identifiers are published both as Terraform outputs and as SSM parameters:

| SSM parameter | Type | Value |
| --- | --- | --- |
| `/platform/<env>/vpc/id` | String | VPC ID |
| `/platform/<env>/vpc/cidr` | String | VPC CIDR |
| `/platform/<env>/subnets/public/ids` | StringList | Public subnet IDs |
| `/platform/<env>/subnets/private/ids` | StringList | Private subnet IDs |
| `/platform/<env>/dns/zone-id` | String | Hosted zone ID |
| `/platform/<env>/dns/zone-name` | String | Hosted zone name |
| `/platform/<env>/dns/domain-name` | String | Environment domain |
| `/platform/<env>/acm/certificate-arn` | String | Validated certificate ARN |
| `/platform/<env>/kms/rds/arn` | String | RDS key ARN |
| `/platform/<env>/kms/efs/arn` | String | EFS key ARN |
| `/platform/<env>/kms/secrets/arn` | String | Secrets Manager key ARN |

Reading them in the application repo:

```hcl
data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/platform/${var.environment}/subnets/private/ids"
}

locals {
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}
```

## Remote state

State lives in the bucket created by [`bootstrap/`](bootstrap/README.md). Both environments share the bucket and use separate keys:

| Environment | Backend file | State key |
| --- | --- | --- |
| dev | `config/dev.backend` | `platform/dev/terraform.tfstate` |
| prod | `config/prod.backend` | `platform/prod/terraform.tfstate` |

Locking uses an S3 lock file (`use_lockfile = true`, Terraform 1.10+), so no DynamoDB table is needed. The GitHub Actions roles from bootstrap can only reach their own environment's `platform/<env>/` folder.

## Running locally

Requires Terraform 1.10+ and AWS credentials with admin access to the account.

```bash
aws sts get-caller-identity
```

Dev (prod is the same with `prod` in place of `dev`):

```bash
terraform init -reconfigure -backend-config=config/dev.backend
```

```bash
terraform plan -var-file=config/dev.tfvars
```

```bash
terraform apply -var-file=config/dev.tfvars
```

Always run `init -reconfigure` with the matching backend file when switching environments. Planning prod variables against dev state would try to turn dev into prod.

To use a named AWS CLI profile, prefix the commands with `AWS_PROFILE=<profile>`.

## CI/CD

GitHub Actions authenticates to AWS through OIDC using the roles created in [`bootstrap/`](bootstrap/README.md), so no AWS keys are stored in GitHub. See the bootstrap README for the GitHub environments and secrets to configure.

## Cost notes

NAT Gateways are billed per hour (about $32/month each) plus data processed. Dev runs one; prod runs one per AZ so an AZ outage doesn't cut outbound internet for the other AZs. Each KMS key costs about $1/month.
