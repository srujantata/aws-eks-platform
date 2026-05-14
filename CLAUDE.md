# aws-eks-platform — LLM Context

## What This Repo Does
Terraform code for the AWS EKS platform. Provisions VPC, EKS cluster, node groups, Karpenter autoscaler, and all EKS add-ons (EBS CSI, EFS CSI, ALB controller). Phase 0 bootstrap also lives here.

## Project Status
- **Current mode: POC** — single-AZ, t3.small nodes, no NAT gateway, ~$59/2wks, destroy when done
- **Production design** documented in `COST.md` and the plan (multi-AZ, m5.xlarge, Karpenter Spot, active-passive DR)

## Directory Structure
```
terraform/
├── global/              ← Phase 0: run FIRST — creates S3 state, DynamoDB lock, GitHub OIDC, IAM role
│   ├── main.tf          ← S3 bucket + DynamoDB + OIDC provider + GitHubActionsRole
│   ├── variables.tf     ← primary_region, dr_region, github_org, tags
│   ├── outputs.tf       ← state bucket name, role ARN, backend config snippet
│   └── terraform.tfvars.example  ← copy to terraform.tfvars, gitignored
├── modules/
│   ├── vpc/             ← VPC, subnets, NAT, IGW (reusable)
│   ├── eks/             ← EKS cluster + managed node groups + OIDC
│   ├── karpenter/       ← NodePool + NodeClass
│   └── addons/          ← EBS CSI, EFS CSI, ALB controller, ArgoCD
└── environments/
    ├── poc/             ← ACTIVE — single-AZ, t3.small, public subnets, no NAT
    ├── dev/
    ├── staging/
    └── prod/            ← Production-spec: multi-AZ, m5.xlarge, Karpenter, HA

scripts/
├── destroy-all.sh       ← Safe teardown: ArgoCD → Helm → LB → terraform destroy
└── destroy-all.ps1      ← Windows equivalent

.github/workflows/
├── terraform-plan.yml   ← Triggers on PR: plan + comment on PR (OIDC auth, no secrets)
└── terraform-apply.yml  ← Triggers on push to main: apply dev auto, staging/prod gated
```

## Key Conventions
- **State backend**: S3 bucket `devops-tfstate-<account-id>`, DynamoDB table `terraform-lock`
- **Auth**: GitHub Actions uses OIDC — role `GitHubActionsRole`, no `AWS_ACCESS_KEY_ID` ever in secrets
- **Tagging**: all resources get `Project=devops-platform`, `ManagedBy=terraform`, `Owner=srujantata`
- **Storage**: EBS gp3 for block storage, EFS for shared (Bitbucket/Jenkins), S3 for Artifactory
- **Terraform version**: >= 1.8, provider `hashicorp/aws ~> 5.0`

## Bootstrap Order (run once, manually)
```bash
cd terraform/global
cp terraform.tfvars.example terraform.tfvars
# Set github_org = "srujantata"
terraform init
terraform apply
# Outputs the S3 bucket name — use in all other backend configs
```

## POC Deploy
```bash
cd terraform/environments/poc
terraform init -backend-config="bucket=devops-tfstate-<ACCOUNT_ID>" \
               -backend-config="key=poc/terraform.tfstate" \
               -backend-config="region=us-east-1" \
               -backend-config="dynamodb_table=terraform-lock"
terraform plan
terraform apply
```

## Teardown (IMPORTANT — destroys everything to avoid charges)
```powershell
# Windows
.\scripts\destroy-all.ps1
# Or directly:
cd terraform/environments/poc && terraform destroy -auto-approve
```

## GitHub Actions Secrets Required
| Secret | Value |
|--------|-------|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `TF_STATE_BUCKET` | `devops-tfstate-<account-id>` |

## What NOT to Do
- Never commit `.tfvars` files (gitignored) — they contain account IDs
- Never add `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` as GitHub secrets — OIDC handles auth
- Never run `terraform apply` on prod without PR review + environment approval gate
- Never leave the POC cluster running overnight if not actively working — costs accumulate

## Related Repos
- `devops-toolchain-helm` — Helm values for Jenkins/Artifactory/SonarQube deployed on this cluster
- `github-actions-iac` — reusable workflow templates referenced by this repo
- `dr-failover-runbook` — DR Terraform for us-west-2 standby (production phase)
