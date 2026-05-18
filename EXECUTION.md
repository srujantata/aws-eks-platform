# DevOps Platform — Full Execution Guide

## Overview
AI-driven prompt-to-infrastructure DevOps platform on AWS EKS. This guide covers every step from account creation to running toolchain to teardown.

**Repos:**
| Repo | Purpose |
|------|---------|
| [aws-eks-platform](https://github.com/srujantata/aws-eks-platform) | EKS cluster Terraform |
| [infra-prompt-engine](https://github.com/srujantata/infra-prompt-engine) | Claude API → Terraform → GitHub PR |
| [devops-toolchain-helm](https://github.com/srujantata/devops-toolchain-helm) | Helm + ArgoCD for Jenkins/Artifactory/SonarQube/Harbor |
| [github-actions-iac](https://github.com/srujantata/github-actions-iac) | Reusable CI/CD workflows (OIDC) |
| [dr-failover-runbook](https://github.com/srujantata/dr-failover-runbook) | Active-passive DR documentation |

---

## Prerequisites

### 1. AWS Account
- Create account at https://aws.amazon.com
- Choose **Paid Plan** (required for EKS access)
- New accounts get **$200 free credits** — POC costs ~$59, leaving $141 unused
- Set billing alert at $20/month (Billing → Budgets → Create budget)

### 2. IAM User (do NOT use root)
```
AWS Console → IAM → Users → Create user
  Name: devops-admin
  Permissions: AdministratorAccess (attach directly)
  Access key: Application running outside AWS
  → Download credentials.csv
```

### 3. Install Required Tools (Windows)

**Option A — winget (recommended)**
```powershell
winget install --id Hashicorp.Terraform --accept-package-agreements --accept-source-agreements
winget install --id Amazon.AWSCLI --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli --accept-package-agreements --accept-source-agreements
```

**Option B — Chocolatey**
```powershell
choco install terraform awscli gh -y
```

**Verify installs** (open new PowerShell after install):
```powershell
terraform version   # should show >= 1.8
aws --version       # should show >= 2.x
gh --version        # should show >= 2.x
git --version       # should show >= 2.x
```

> Note: After winget install, binaries may not be in PATH until a new terminal session is opened. If `terraform` is not found, use full path: `C:\Users\<USER>\AppData\Local\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe`

### 4. Configure AWS CLI
```powershell
aws configure
# AWS Access Key ID:     (from credentials.csv)
# AWS Secret Access Key: (from credentials.csv)
# Default region:        us-east-1
# Default output format: json
```

**Verify:**
```powershell
aws sts get-caller-identity
# Expected output:
# {
#     "UserId": "AIDAUJ56JKOU6P3ET27YO",
#     "Account": "296214942633",
#     "Arn": "arn:aws:iam::296214942633:user/devops-admin"
# }
```

### 5. Authenticate GitHub CLI
```powershell
gh auth login
# Choose: GitHub.com → HTTPS → Login with a web browser
# After login, add workflow scope:
gh auth refresh -s workflow
```

**Verify:**
```powershell
gh auth status
```

### 6. Clone all repos
```powershell
Set-Location "D:\Srujan\Claude\devops"
gh repo clone srujantata/aws-eks-platform
gh repo clone srujantata/infra-prompt-engine
gh repo clone srujantata/devops-toolchain-helm
gh repo clone srujantata/github-actions-iac
gh repo clone srujantata/dr-failover-runbook
```

---

## Phase 0 — Bootstrap (Run Once)

**What this creates:**
- S3 bucket for Terraform remote state (`devops-tfstate-296214942633`)
- DynamoDB table for state locking (`terraform-lock`)
- GitHub OIDC provider in AWS IAM (keyless auth for GitHub Actions)
- IAM role `GitHubActionsRole` (assumed by GitHub Actions via OIDC)

**Run time:** ~2 minutes  
**Cost:** ~$0.02/month (S3 + DynamoDB negligible)

```powershell
# 1. Enter global directory
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\global"

# 2. Create tfvars (gitignored — safe)
@"
primary_region = "us-east-1"
dr_region      = "us-west-2"
github_org     = "srujantata"
"@ | Out-File -FilePath terraform.tfvars -Encoding utf8

# 3. Init (local state — bootstrap is the chicken-and-egg exception)
terraform init

# 4. Preview changes
terraform plan

# 5. Apply
terraform apply
# Type: yes

# 6. Save outputs (you'll need these for later steps)
terraform output
```

**Expected outputs:**
```
state_bucket_name       = "devops-tfstate-296214942633"
lock_table_name         = "terraform-lock"
github_oidc_provider_arn = "arn:aws:iam::296214942633:oidc-provider/token.actions.githubusercontent.com"
github_actions_role_arn  = "arn:aws:iam::296214942633:role/GitHubActionsRole"
```

### Add GitHub Actions Secrets (required for CI/CD)
```
GitHub → aws-eks-platform repo → Settings → Secrets → Actions → New secret

Secret 1: AWS_ACCOUNT_ID    = 296214942633
Secret 2: TF_STATE_BUCKET   = devops-tfstate-296214942633
```

---

## Phase 2 — POC EKS Cluster

**What this creates:**
- VPC with public subnets (single AZ — us-east-1a, POC only)
- EKS 1.30 cluster
- 2× t3.small worker nodes (On-Demand)
- EBS CSI driver (gp3 storage class)
- AWS Load Balancer Controller

**Run time:** ~15 minutes  
**POC cost:** ~$4.30/day (~$59 for 14 days)

```powershell
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"

# Init with remote state backend
terraform init `
  -backend-config="bucket=devops-tfstate-296214942633" `
  -backend-config="key=poc/terraform.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="dynamodb_table=terraform-lock"

terraform plan
terraform apply
# Type: yes

# Configure kubectl
aws eks update-kubeconfig --name devops-poc --region us-east-1

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

**Expected output:**
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-x-x.ec2.internal     Ready    <none>   2m    v1.30.x
ip-10-0-x-x.ec2.internal     Ready    <none>   2m    v1.30.x
```

---

## Phase 2 — Actual Deployment Results

**Date deployed:** 2026-05-18

### Cluster Details
| Field | Value |
|-------|-------|
| Cluster name | `devops-poc` |
| Kubernetes version | 1.30 |
| Region | us-east-1 |
| Cluster endpoint | `https://3D6DF603FA21813ADA47B266178C114F.gr7.us-east-1.eks.amazonaws.com` |
| VPC ID | `vpc-0555202bdcb47a294` |

### Node Status
| Node | AZ | Public IP | Version | Status |
|------|----|-----------|---------|--------|
| ip-10-0-1-140.ec2.internal | us-east-1a | 98.92.178.207 | v1.30.14-eks-7fcd7ec | Ready |
| ip-10-0-2-129.ec2.internal | us-east-1b | 44.212.77.42 | v1.30.14-eks-7fcd7ec | Ready |

### EKS Add-ons Active
| Add-on | Status |
|--------|--------|
| coredns | ACTIVE |
| kube-proxy | ACTIVE |
| vpc-cni | ACTIVE |
| aws-ebs-csi-driver | ACTIVE |

### Storage
- **StorageClass:** `ebs-gp3` (default, gp3, encrypted)

### Configure kubectl
```powershell
aws eks update-kubeconfig --name devops-poc --region us-east-1
```

### Lessons Learned — Issues & Fixes

**Issue 1: EKS requires 2 AZs minimum**
- **Symptom:** `terraform apply` failed — EKS control plane rejected single-AZ VPC
- **Fix:** Added a second subnet in `us-east-1b` to `terraform/environments/poc/main.tf`
- **Lesson:** Always provision EKS subnets across at least 2 AZs, even for POC

**Issue 2: Public subnets need `map_public_ip_on_launch = true`**
- **Symptom:** Worker nodes launched without public IPs and could not reach the EKS API server
- **Fix:** Set `map_public_ip_on_launch = true` in subnet resource, then patched existing subnets via AWS CLI:
  ```powershell
  aws ec2 modify-subnet-attribute --subnet-id <id> --map-public-ip-on-launch
  ```
- **Lesson:** Terraform doesn't auto-patch this on existing subnets — use AWS CLI for in-place fixes

**Issue 3: EBS CSI driver needs `AmazonEBSCSIDriverPolicy` on the node IAM role**
- **Symptom:** PersistentVolumeClaims stuck in `Pending`; `aws-ebs-csi-driver` pods crashlooping
- **Fix:** Added `AmazonEBSCSIDriverPolicy` to `iam_role_additional_policies` in the EKS node group module
- **Lesson:** EBS CSI is an EKS-managed add-on but still requires explicit IAM policy attachment on nodes

---

## Phase 3 — DevOps Toolchain (ArgoCD + Helm)

**What this deploys:** Jenkins, SonarQube, Harbor (POC tier — single replica, minimal resources)

```powershell
# Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace --wait

# Get ArgoCD initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward ArgoCD UI (open browser at http://localhost:8080)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Apply App-of-Apps (deploys all tools)
kubectl apply -f argocd/bootstrap/app-of-apps.yaml

# Watch sync progress
kubectl get applications -n argocd -w
```

---

## Phase 3 — Actual Deployment Results
*Deployed: 2026-05-18*

### Node Upgrade: t3.small → t3.medium
SonarQube 2026.x (Elasticsearch 8 + JVM) requires minimum 1.6 GB RAM.
t3.small left only ~920 MB after system pods — OOMKill on every attempt.
Upgraded to t3.medium (3.75 GB allocatable). Cost delta: +$1/day (~$14 for 2-week POC).

| Node | Instance | RAM | AZ | Status |
|------|----------|-----|----|--------|
| ip-10-0-1-219.ec2.internal | t3.medium | 3.75 GB | us-east-1a | Ready |
| ip-10-0-2-10.ec2.internal | t3.medium | 3.75 GB | us-east-1b | Ready |

### Tools Deployed

| Tool | Chart Version | Namespace | Status |
|------|--------------|-----------|--------|
| ArgoCD | argo-cd-9.5.14 (v3.4.2) | argocd | ✅ 7/7 pods Running |
| Jenkins | jenkins-5.9.22 (2.552.x) | jenkins | ✅ 2/2 Running |
| SonarQube | sonarqube-2026.2.x Community | sonarqube | ✅ 1/1 Running |

### Access URLs & Credentials

> ⚠️ These are ephemeral AWS ALB hostnames — they change on each `terraform destroy/apply` cycle.
> In production use Route53 with a stable domain name.

**ArgoCD** (GitOps dashboard)
- URL: `http://a944fe58b20d24057b8cf0af7f586c3a-245014201.us-east-1.elb.amazonaws.com`
- Username: `admin`
- Password: `kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

**Jenkins** (CI/CD)
- URL: `http://a910314d11cee49a99b923e221108e05-468852420.us-east-1.elb.amazonaws.com:8080`
- Username: `admin`
- Password: `kubectl get secret jenkins -n jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d`

**SonarQube** (Code quality)
- URL: `http://a386f7224766d43d6b50aeee825abe34-1292105297.us-east-1.elb.amazonaws.com:9000`
- Username: `admin`
- Password: `admin` ← change on first login

### Lessons Learned — Phase 3

| # | Issue | Fix | Takeaway |
|---|-------|-----|----------|
| 1 | SonarQube OOMKill on t3.small | Upgraded to t3.medium | SonarQube needs 1.6 GB min (ES 8 + 2 JVMs) |
| 2 | `edition=community` rejected | Use `community.enabled=true` | Chart API changed in 2026.x versions |
| 3 | SonarQube needs monitoringPasscode | Added `--set monitoringPasscode=...` | Required in newer chart versions |

### Helm Values in GitHub
All POC values committed to [devops-toolchain-helm](https://github.com/srujantata/devops-toolchain-helm):
- `charts/jenkins/values.yaml`
- `charts/sonarqube/values.yaml`

---

## Phase 5 — Teardown (IMPORTANT — run before credits run out)

**Always destroy in this order to avoid orphaned AWS resources (LBs, EBS volumes) that continue charging:**

```powershell
# Step 1 — Delete ArgoCD apps first (removes LBs and PVCs cleanly)
kubectl delete applications --all -n argocd

# Step 2 — Remove Helm releases
helm uninstall argocd -n argocd
helm uninstall aws-load-balancer-controller -n kube-system

# Step 3 — Wait for LBs to fully delete (~2 min)
aws elb describe-load-balancers --region us-east-1
# Repeat until empty

# Step 4 — Destroy EKS cluster
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"
terraform destroy
# Type: yes
# Takes ~10 minutes

# Step 5 — Destroy bootstrap (optional — costs ~$0.02/month to keep)
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\global"
terraform destroy
# Type: yes

# Step 6 — Verify no running resources
aws ec2 describe-instances --region us-east-1 --filters "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId"
aws eks list-clusters --region us-east-1
# Both should return empty
```

---

## Cost Reference

| Phase | Resources | Daily cost | 14-day cost |
|-------|-----------|-----------|-------------|
| POC EKS | 2× t3.small + EKS control plane | ~$4.30 | ~$60 |
| Bootstrap only | S3 + DynamoDB | ~$0.001 | ~$0.01 |
| **Total POC** | | **~$4.30/day** | **~$60** |
| **AWS credits** | New account | — | **$200** |
| **Out of pocket** | | | **$0** |

> Production costs: ~$2,400/month (see COST.md)

---

## Billing Safety Checklist
- [ ] Billing alert set at $20/month (AWS Billing → Budgets)
- [ ] Destroy EKS before leaving POC running for >14 days
- [ ] After destroy: verify `aws eks list-clusters` returns empty
- [ ] After destroy: verify `aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"` returns empty
- [ ] Bootstrap (S3+DynamoDB) can stay — costs $0.01/month, holds your state

---

## Troubleshooting

### terraform not found in PATH
```powershell
# Use full path
$tf = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Filter "terraform.exe" -Recurse | Select -First 1).FullName
& $tf version
```

### kubectl not configured
```powershell
aws eks update-kubeconfig --name devops-poc --region us-east-1
kubectl get nodes
```

### GitHub Actions failing with "credentials"
- Ensure `AWS_ACCOUNT_ID` and `TF_STATE_BUCKET` secrets are set in repo Settings → Secrets
- OIDC role trust policy must include your repo: `repo:srujantata/*:*`
- Role created by Phase 0 bootstrap — must run that first

### EKS nodes NotReady
```powershell
kubectl describe nodes
kubectl get pods -n kube-system
# Check aws-node (VPC CNI) and coredns pods are Running
```

---

*Last updated: 2026-05-18 | Author: Srujan Tata | AWS Account: 296214942633*
