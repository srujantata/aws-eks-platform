# aws-eks-platform

![Terraform](https://img.shields.io/badge/Terraform-1.8-7B42BC?logo=terraform)
![EKS](https://img.shields.io/badge/EKS-1.30-FF9900?logo=amazon-aws)
![AWS](https://img.shields.io/badge/AWS-us--east--1-FF9900?logo=amazon-aws)
![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo)
![License](https://img.shields.io/badge/license-MIT-blue)

> Production-grade EKS cluster built entirely with Terraform.
> Hosts a full DevOps toolchain — Jenkins, SonarQube, Harbor, ArgoCD.
> Administered via natural language through the [infra-prompt-engine](https://github.com/srujantata/infra-prompt-engine).

---

## What's Running (Live — us-east-1)

| Tool | URL | Credentials | Status |
|------|-----|-------------|--------|
| **ArgoCD** | http://a944fe58b20d24057b8cf0af7f586c3a-245014201.us-east-1.elb.amazonaws.com | admin / see kubectl secret | ✅ Live |
| **Jenkins** | http://a910314d11cee49a99b923e221108e05-468852420.us-east-1.elb.amazonaws.com:8080 | admin / `s3TMPc1dfyrWzAj9zLyGgx` | ✅ Live |
| **SonarQube** | http://a386f7224766d43d6b50aeee825abe34-1292105297.us-east-1.elb.amazonaws.com:9000 | admin / admin | ✅ Live |
| **Harbor** | http://a68756541aa5a454d81e6515e061e3c2-574233704.us-east-1.elb.amazonaws.com | admin / Harbor12345 | ✅ Live |

> **Note:** LoadBalancer hostnames change after `terraform destroy/apply`. Always get current URLs from:
> ```bash
> kubectl get svc -A | grep LoadBalancer
> ```

---

## Architecture

### POC (Deployed)

```
AWS us-east-1 — Account 296214942633
└── VPC (10.0.0.0/16)
    ├── Public Subnet us-east-1a (10.0.1.0/24)
    └── Public Subnet us-east-1b (10.0.2.0/24)   ← EKS requires 2 AZs minimum
        └── EKS 1.30  (terraform-aws-modules/eks v20)
            ├── Node Group: 2× t3.medium On-Demand
            │   └── IAM: AmazonEBSCSIDriverPolicy attached
            ├── Add-ons: EBS CSI | CoreDNS | kube-proxy | VPC-CNI
            └── ArgoCD (App-of-Apps GitOps)
                ├── Jenkins    (jenkins/jenkins 5.9.22)
                ├── SonarQube  (sonarqube/sonarqube 2026.x)
                └── Harbor     (harbor/harbor 1.19.0)
```

### Production Design (documented, not deployed)

```
AWS us-east-1 (Primary)          AWS us-west-2 (Standby — passive)
└── VPC 3-AZ                     └── VPC 3-AZ (warm standby)
    ├── Private subnets + NAT         ├── EKS cluster (scaled down)
    ├── EKS 6× m5.2xlarge             └── Read replicas only
    ├── Aurora Global DB (write)
    ├── S3 with CRR → us-west-2
    ├── EFS with replication
    └── Route53 health-check failover
        → RTO: 30 min | RPO: 5 min
```

---

## POC vs Production

| | POC (this repo) | Production design |
|--|-----------------|-------------------|
| **AZs** | 2 (EKS minimum) | 3 |
| **Nodes** | 2× t3.medium | 6× m5.2xlarge |
| **Subnets** | Public only (no NAT) | Private + NAT per AZ |
| **Database** | Embedded H2 / in-cluster PG | Aurora Global DB |
| **Storage** | EBS gp3 | EBS + EFS |
| **Autoscaling** | Fixed node group | Karpenter + KEDA |
| **Secrets** | Env vars | External Secrets Operator + AWS SM |
| **DR** | None | Active-passive us-west-2 |
| **Cost** | ~$120/month | ~$2,100/month |
| **2-week total** | ~$60 | ~$1,050 |

---

## Repository Structure

```
aws-eks-platform/
│
├── terraform/
│   ├── global/
│   │   └── main.tf           ← Bootstrap: S3 state, DynamoDB lock, OIDC, IAM
│   └── environments/
│       └── poc/
│           ├── main.tf        ← VPC, EKS cluster, node group, StorageClass
│           ├── variables.tf
│           └── outputs.tf
│
├── EXECUTION.md               ← Step-by-step deploy guide with real results
├── TEARDOWN.md                ← Ordered destroy steps (saves ~$53/day)
├── TEST_RESULTS.md            ← All phase results, bugs fixed, live verification
└── README.md
```

---

## Quick Start

### Prerequisites

```bash
# Install tools (Windows)
winget install Hashicorp.Terraform Amazon.AWSCLI GitHub.cli

# Verify
terraform version   # >= 1.8
aws --version
gh --version

# Configure credentials
aws configure       # enter Access Key ID + Secret
gh auth login       # browser login → select GitHub.com → HTTPS
```

### Phase 0 — Bootstrap (run once per AWS account)

Creates: S3 state bucket, DynamoDB lock table, GitHub OIDC provider, IAM role.

```bash
cd terraform/global
terraform init
terraform apply
# Note the outputs: state_bucket_name, dynamodb_table_name
```

### Phase 1 — Deploy EKS Cluster

```bash
cd terraform/environments/poc

# Step 1: Deploy VPC + EKS (before kubernetes provider can authenticate)
terraform init
terraform apply -target=module.vpc -target=module.eks

# Step 2: Full apply (StorageClass + anything else)
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name devops-poc --region us-east-1
kubectl get nodes   # 2× t3.medium Ready
```

### Deploy DevOps Toolchain

```bash
# ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace

# Jenkins
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins -n jenkins --create-namespace \
  -f https://raw.githubusercontent.com/srujantata/devops-toolchain-helm/master/charts/jenkins/values.yaml

# SonarQube
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm install sonarqube sonarqube/sonarqube -n sonarqube --create-namespace \
  -f https://raw.githubusercontent.com/srujantata/devops-toolchain-helm/master/charts/sonarqube/values.yaml \
  --set monitoringPasscode=admin123

# Harbor
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor -n harbor --create-namespace \
  -f https://raw.githubusercontent.com/srujantata/devops-toolchain-helm/master/charts/harbor/values.yaml
```

### Destroy (stop billing — ~$53/day if left running)

```bash
# 1. Uninstall Helm releases (removes LoadBalancers from AWS)
helm uninstall harbor -n harbor
helm uninstall sonarqube -n sonarqube
helm uninstall jenkins -n jenkins
helm uninstall argocd -n argocd

# 2. Delete PVCs (releases EBS volumes)
kubectl delete pvc --all -n jenkins
kubectl delete pvc --all -n sonarqube
kubectl delete pvc --all -n harbor

# 3. Wait 2 minutes for ALBs to deregister
Start-Sleep -Seconds 120

# 4. Destroy EKS + VPC
cd terraform/environments/poc
terraform destroy -auto-approve

# 5. Optional: destroy bootstrap (loses state bucket)
# cd terraform/global && terraform destroy -auto-approve
```

---

## Key Infrastructure Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| IaC tool | Terraform | Best EKS module ecosystem (`terraform-aws-modules/eks v20`) |
| GitOps | ArgoCD | Web UI for visibility; App-of-Apps pattern scales well |
| Autoscaling (prod) | Karpenter | 3-4× faster than Cluster Autoscaler; native Spot support |
| Secrets (prod) | External Secrets Operator | IRSA-based; no secrets in Git |
| State backend | S3 + DynamoDB | Standard, reliable, supports team locking |
| Node type | t3.medium | SonarQube requires 1.6GB free RAM minimum — t3.small OOMKills |
| Subnets | Public (POC only) | Removes NAT Gateway cost (~$32/month saved) |
| StorageClass | EBS gp3 | 20% cheaper than gp2 at same IOPS; encrypted by default |

---

## Bugs Fixed During Build

| Bug | Symptom | Fix |
|-----|---------|-----|
| IAM role description | `CreateRole` failed with `InvalidInputException` | Replaced em dash `—` with plain hyphen `-` (AWS rejects non-ASCII) |
| EKS single-AZ | `UnsupportedAvailabilityZoneException` | EKS requires subnets in ≥2 AZs — added us-east-1b subnet |
| Nodes no internet | Pods stuck `ContainerCreating`, image pulls failed | Added `map_public_ip_on_launch = true` to public subnets |
| EBS CSI crashloop | `ec2:DescribeAvailabilityZones` access denied | Attached `AmazonEBSCSIDriverPolicy` to node IAM role |
| SonarQube OOMKill | Pod killed 30s after start, ES8 needs 1.6GB | Upgraded nodes t3.small → t3.medium |
| SonarQube chart API | `Unknown field: edition` error | Replaced `edition=community` with `community.enabled=true` |

---

## AI Administration

This cluster is fully administered through natural language via [infra-prompt-engine](https://github.com/srujantata/infra-prompt-engine).

```bash
# "Is my cluster healthy?" → kubectl get pods/nodes → AI summary
# "Scale Jenkins to 3 replicas" → kubectl scale deployment jenkins --replicas=3 -n jenkins
# "Add a Redis cache" → Terraform HCL generated → GitHub PR opened
```

Chat UI (PWA — works on mobile): see [infra-prompt-engine/chat_ui](https://github.com/srujantata/infra-prompt-engine/tree/master/chat_ui)

---

## Related Repos

| Repo | Purpose |
|------|---------|
| [infra-prompt-engine](https://github.com/srujantata/infra-prompt-engine) | AI prompt → Terraform/kubectl admin layer |
| [devops-toolchain-helm](https://github.com/srujantata/devops-toolchain-helm) | Helm values for all tools |
| [github-actions-iac](https://github.com/srujantata/github-actions-iac) | Reusable CI/CD workflows + OIDC |
| [dr-failover-runbook](https://github.com/srujantata/dr-failover-runbook) | Active-passive DR, RTO 30min / RPO 5min |

---

## Skills Demonstrated

`Terraform` · `AWS EKS` · `VPC networking` · `IAM / IRSA` · `Helm` · `ArgoCD` · `GitOps` · `GitHub Actions OIDC` · `EBS CSI` · `Cost optimisation` · `HA architecture` · `Active-passive DR` · `Kubernetes` · `DevSecOps`
