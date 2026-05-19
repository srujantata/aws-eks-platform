# Teardown Guide — Destroy All Infrastructure

> Last executed: 2026-05-18 | Result: 55 resources destroyed, $0 AWS spend
> Everything is in GitHub — rebuild in ~20 minutes anytime.

---

## Cost if Left Running

| Resource | Rate | Per Day |
|----------|------|---------|
| EKS Control Plane | $0.10/hr | $2.40 |
| 2× t3.medium nodes | $0.0416/hr each | $2.00 |
| 4× Classic LoadBalancers | $0.025/hr each | $2.40 |
| 5× EBS volumes (~50Gi gp3) | $0.08/Gi/month | $0.40 |
| CloudWatch Logs | $0.50/GB | ~$0.10 |
| **Total** | | **~$7.30/day (~$220/month)** |

> Bootstrap (S3 + DynamoDB) costs ~$0.02/day — keep it, it's needed to rebuild.

---

## Teardown Order — MUST follow this sequence

> **Wrong order = orphaned LoadBalancers still billing you in AWS even after terraform destroy**
> Helm uninstall first → LBs removed from AWS → then terraform destroy is safe.

### Step 1 — Uninstall Helm releases (removes LoadBalancers)

```powershell
helm uninstall harbor    -n harbor
helm uninstall sonarqube -n sonarqube
helm uninstall jenkins   -n jenkins
helm uninstall argocd    -n argocd
```

Expected output:
```
release "harbor" uninstalled
release "sonarqube" uninstalled
release "jenkins" uninstalled
release "argocd" uninstalled
```

> ArgoCD will keep CRDs (`applications.argoproj.io` etc) — this is normal, Terraform handles them.

---

### Step 2 — Delete PVCs (releases EBS volumes from billing)

```powershell
kubectl delete pvc --all -n jenkins
kubectl delete pvc --all -n sonarqube
kubectl delete pvc --all -n harbor
kubectl delete pvc --all -n argocd
```

Harbor keeps PVCs with a resource policy — the explicit delete above overrides it.

---

### Step 3 — Wait for LoadBalancers to deregister from AWS (~90 seconds)

```powershell
Start-Sleep -Seconds 90

# Verify LBs are gone before terraform destroy
aws elb describe-load-balancers --region us-east-1 `
  --query "LoadBalancerDescriptions[].LoadBalancerName"
# Expected: []

aws elbv2 describe-load-balancers --region us-east-1 `
  --query "LoadBalancers[].LoadBalancerArn"
# Expected: []
```

> If LBs still appear: wait another 60s and check again. Do NOT run terraform destroy until they're gone.

---

### Step 4 — Terraform destroy (EKS + VPC + all resources)

```powershell
$tf = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" `
       -Filter "terraform.exe" -Recurse -ErrorAction SilentlyContinue | `
       Select-Object -First 1).FullName

cd "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"
& $tf destroy -auto-approve
```

**Takes ~10–15 minutes.** What gets destroyed (55 resources):
- EKS cluster + managed node group
- 2× EC2 t3.medium instances
- VPC, 2× public subnets, route tables, internet gateway
- IAM roles + policies (cluster role, node role, IRSA roles)
- Security groups
- KMS key (EKS secrets encryption)
- CloudWatch log group
- EBS CSI StorageClass

Expected final line:
```
Destroy complete! Resources: 55 destroyed.
```

---

### Step 5 — Verify everything is gone

```powershell
# No EKS clusters
aws eks list-clusters --region us-east-1
# Expected: {"clusters": []}

# No running EC2 instances
aws ec2 describe-instances --region us-east-1 `
  --filters "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[].InstanceId"
# Expected: []

# No LoadBalancers
aws elb describe-load-balancers --region us-east-1 `
  --query "LoadBalancerDescriptions[].LoadBalancerName"
# Expected: []

# No EBS volumes (except any manually created ones)
aws ec2 describe-volumes --region us-east-1 `
  --filters "Name=status,Values=available" `
  --query "Volumes[].VolumeId"
# Expected: []
```

---

### Step 6 (Optional) — Destroy bootstrap

**Do NOT do this unless you want to fully reset the AWS account.**
The S3 bucket + DynamoDB table cost ~$0.02/day and are required to rebuild.

```powershell
cd "D:\Srujan\Claude\devops\aws-eks-platform\terraform\global"
& $tf destroy -auto-approve
```

> If you destroy bootstrap, you must re-run Phase 0 before rebuilding the cluster.

---

## Quick Teardown (One Block — Verified 2026-05-18)

```powershell
# Configure kubectl
aws eks update-kubeconfig --name devops-poc --region us-east-1

# Step 1: Uninstall tools
helm uninstall harbor    -n harbor    2>&1
helm uninstall sonarqube -n sonarqube 2>&1
helm uninstall jenkins   -n jenkins   2>&1
helm uninstall argocd    -n argocd    2>&1

# Step 2: Release EBS volumes
kubectl delete pvc --all -n jenkins
kubectl delete pvc --all -n sonarqube
kubectl delete pvc --all -n harbor

# Step 3: Wait for ALBs to deregister
Start-Sleep -Seconds 90

# Step 4: Destroy EKS + VPC
$tf = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Filter "terraform.exe" -Recurse -EA 0 | Select -First 1).FullName
cd "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"
& $tf destroy -auto-approve
```

---

## Rebuild From Zero (~20 Minutes)

Everything is in GitHub. Run this to bring it all back:

```powershell
# Step 1: Recreate EKS cluster
cd "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"
& $tf init
& $tf apply -target=module.vpc -target=module.eks -auto-approve   # ~12 min
& $tf apply -auto-approve                                          # ~2 min (StorageClass)

# Step 2: Configure kubectl
aws eks update-kubeconfig --name devops-poc --region us-east-1
kubectl get nodes   # wait for 2x Ready

# Step 3: Reinstall all tools
helm repo add argo       https://argoproj.github.io/argo-helm
helm repo add jenkins    https://charts.jenkins.io
helm repo add sonarqube  https://SonarSource.github.io/helm-chart-sonarqube
helm repo add harbor     https://helm.goharbor.io
helm repo update

helm install argocd    argo/argo-cd        -n argocd    --create-namespace
helm install jenkins   jenkins/jenkins     -n jenkins   --create-namespace `
  -f D:\Srujan\Claude\devops\devops-toolchain-helm\charts\jenkins\values.yaml
helm install sonarqube sonarqube/sonarqube -n sonarqube --create-namespace `
  -f D:\Srujan\Claude\devops\devops-toolchain-helm\charts\sonarqube\values.yaml `
  --set monitoringPasscode=admin123
helm install harbor    harbor/harbor       -n harbor    --create-namespace `
  -f D:\Srujan\Claude\devops\devops-toolchain-helm\charts\harbor\values.yaml

# Step 4: Get new LoadBalancer URLs
kubectl get svc -A | Select-String LoadBalancer
```

> New LoadBalancer hostnames will differ from previous ones — AWS assigns new DNS names each time.
> Update `EXECUTION.md` and `ALERTS.txt` with the new URLs.

---

## What Persists After Teardown

| Resource | Persists? | Why |
|----------|-----------|-----|
| S3 state bucket (`devops-tfstate-296214942633`) | Yes | Needed to rebuild |
| DynamoDB lock table (`terraform-lock`) | Yes | Needed to rebuild |
| GitHub OIDC provider | Yes | Needed for GitHub Actions |
| GitHubActionsRole (IAM) | Yes | Needed for CI/CD |
| All GitHub repos + code | Yes | Everything is in Git |
| Helm values in devops-toolchain-helm | Yes | In Git |
| Terraform state file | Yes | In S3 |
| **EKS cluster** | **No** | Destroyed |
| **EC2 nodes** | **No** | Destroyed |
| **LoadBalancers** | **No** | Destroyed |
| **EBS volumes** | **No** | Destroyed |
| **All pod data** | **No** | Not persisted (POC) |

---

## Actual Teardown Log (2026-05-18)

```
18:xx — helm uninstall harbor/sonarqube/jenkins/argocd  → all uninstalled
18:xx — kubectl delete pvc --all (harbor: 5 PVCs deleted)
18:xx — Start-Sleep 90s
18:xx — terraform destroy -auto-approve
        55 resources destroyed
        Duration: ~11 minutes
        Final: "Destroy complete! Resources: 55 destroyed."
18:xx — aws eks list-clusters → {"clusters": []}
        aws ec2 describe-instances → []
```

**Cost stopped at time of destroy.** Bootstrap costs ~$0.50/month ongoing.
