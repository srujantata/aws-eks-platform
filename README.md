# aws-eks-platform

![Terraform](https://img.shields.io/badge/Terraform-1.8-7B42BC?logo=terraform)
![EKS](https://img.shields.io/badge/EKS-1.30-FF9900?logo=amazon-aws)
![License](https://img.shields.io/badge/license-MIT-blue)

Production-grade EKS cluster for a DevOps toolchain — deployed via Terraform, GitOps-managed by ArgoCD. Multi-AZ HA with active-passive DR across `us-east-1` (primary) and `us-west-2` (standby).

## Architecture

```
VPC (10.0.0.0/16) — 3 Availability Zones
├── EKS 1.30 (Terraform aws-eks module v20)
│   ├── System NodeGroup  — On-Demand m5.large × 3
│   ├── Tools NodeGroup   — On-Demand m5.2xlarge × 3
│   └── Karpenter Pool    — Spot/On-Demand, auto-sized
├── Add-ons: EBS CSI | EFS CSI | ALB Controller | Karpenter | KEDA
└── GitOps: ArgoCD (App-of-Apps pattern)
```

## What This Deploys

| Layer | Resource | Details |
|-------|----------|---------|
| Network | VPC, 3 public + 3 private subnets | NAT GW per AZ for HA |
| Compute | EKS 1.30 cluster | Managed node groups + Karpenter |
| Storage | EBS gp3 StorageClass | EFS for shared workloads |
| Ingress | AWS Load Balancer Controller | ALB with ACM TLS |
| GitOps | ArgoCD | App-of-Apps bootstrap |
| DR | Passive EKS in us-west-2 | Aurora Global DB, S3 CRR, EFS replication |

## Phase 0 Bootstrap (Run First)

```bash
cd terraform/global
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set github_org to your GitHub username
terraform init
terraform plan
terraform apply
```

Creates: S3 state bucket, DynamoDB lock table, GitHub OIDC provider, GitHubActionsRole.

## Skills Demonstrated

`Terraform` · `AWS EKS` · `Karpenter` · `ArgoCD` · `IRSA` · `GitOps` · `HA/DR` · `GitHub Actions` · `OIDC`
