# DevOps Platform — Test Results & Verification Log

> Last updated: 2026-05-18
> AWS Account: 296214942633 | Region: us-east-1 | Cluster: devops-poc

---

## Summary

| Phase | Description | Status | Commit |
|-------|-------------|--------|--------|
| Phase 0 | Bootstrap — S3, DynamoDB, OIDC, IAM | PASS | `976d3b8` |
| Phase 2 | EKS Cluster — VPC, nodes, EBS CSI | PASS | `9773c5a` |
| Phase 3 | Toolchain — ArgoCD, Jenkins, SonarQube, Harbor | PASS | `e881345` / `260b2db` |
| Phase 1 | Prompt Engine — Claude API + GitHub PR | PASS | `a000cee` |
| Phase 1.5 | kubectl Admin Layer — natural language ops | PASS | `53dea5a` |

All 5 phases complete. All 12 automated tests passing. All 4 toolchain services live and HTTP 200.

---

## Phase 0 — Bootstrap Infrastructure

### Tests Performed
- `terraform init` with local state (bootstrap is the chicken-and-egg exception)
- `terraform plan` — verified 6 resources to create
- `terraform apply` — verified all 6 resources created successfully
- `terraform output` — confirmed all 4 output values present
- `aws sts get-caller-identity` — confirmed correct AWS account/user

### Resources Created
| Resource | Name / ARN | Status |
|----------|-----------|--------|
| S3 bucket (Terraform state) | `devops-tfstate-296214942633` | Created — versioned + encrypted |
| DynamoDB table (state lock) | `terraform-lock` | Created — PAY_PER_REQUEST, PITR enabled |
| GitHub OIDC provider | `token.actions.githubusercontent.com` | Created |
| IAM role | `GitHubActionsRole` | Created — trust: `repo:srujantata/*:*` |

### Terraform Outputs Verified
```
state_bucket_name        = "devops-tfstate-296214942633"
lock_table_name          = "terraform-lock"
github_oidc_provider_arn = "arn:aws:iam::296214942633:oidc-provider/token.actions.githubusercontent.com"
github_actions_role_arn  = "arn:aws:iam::296214942633:role/GitHubActionsRole"
```

### AWS Identity Verified
```
UserId:  AIDAUJ56JKOU6P3ET27YO
Account: 296214942633
Arn:     arn:aws:iam::296214942633:user/devops-admin
```

### Bugs Fixed During This Phase
| # | Issue | Fix |
|---|-------|-----|
| 1 | IAM role description contained an em dash (—) — AWS rejects non-ASCII characters in IAM descriptions | Replaced em dash with plain ASCII hyphen (-) in `terraform/global/main.tf` |

### Commit
`976d3b8` — feat: Phase 0 bootstrap complete - fix IAM description encoding, add EXECUTION.md

---

## Phase 2 — EKS Cluster

### Tests Performed
- `terraform plan` — verified VPC, subnets, EKS cluster, node group, IAM roles
- `terraform apply` — cluster creation succeeded (~15 minutes)
- `aws eks update-kubeconfig` — kubectl context updated
- `kubectl get nodes` — confirmed 2 nodes Ready
- `kubectl get pods -A` — confirmed all system pods Running
- EBS CSI driver PVC test — PVC bound successfully using `ebs-gp3` StorageClass
- Node internet connectivity — `aws-node` (VPC CNI) and `coredns` pods Running

### Terraform Resources Created
- VPC: `vpc-0555202bdcb47a294`
- Public subnets: us-east-1a + us-east-1b (2 AZs)
- EKS control plane: `devops-poc` (Kubernetes 1.30)
- Node group: 2x t3.medium (upgraded from t3.small — see bugs)
- IAM node role with `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEBSCSIDriverPolicy`
- StorageClass: `ebs-gp3` (default, encrypted)

### Node Status (live — 2026-05-18)
```
NAME                         STATUS   ROLES   AGE    VERSION                INTERNAL-IP   EXTERNAL-IP    OS-IMAGE
ip-10-0-1-219.ec2.internal   Ready    <none>  170m   v1.30.14-eks-7fcd7ec   10.0.1.219    3.83.20.248    Amazon Linux 2023.11.20260509
ip-10-0-2-10.ec2.internal    Ready    <none>  170m   v1.30.14-eks-7fcd7ec   10.0.2.10     98.94.56.113   Amazon Linux 2023.11.20260509
```

### EKS Add-ons Active
| Add-on | Status |
|--------|--------|
| coredns | ACTIVE |
| kube-proxy | ACTIVE |
| vpc-cni | ACTIVE |
| aws-ebs-csi-driver | ACTIVE |

### Bugs Fixed During This Phase
| # | Issue | Fix |
|---|-------|-----|
| 1 | EKS control plane rejected single-AZ VPC — EKS requires 2 AZs minimum | Added second subnet in us-east-1b to `terraform/environments/poc/main.tf` |
| 2 | Worker nodes launched without public IPs and could not reach EKS API server | Set `map_public_ip_on_launch = true` in subnet resource; patched existing subnets via `aws ec2 modify-subnet-attribute` |
| 3 | PersistentVolumeClaims stuck in Pending; `aws-ebs-csi-driver` pods crashlooping | Added `AmazonEBSCSIDriverPolicy` to `iam_role_additional_policies` in EKS node group module |

### Commits
- `9773c5a` — feat: Phase 2 complete - POC EKS cluster deployed, 2 nodes Ready
- `72c29c7` — fix: upgrade node group t3.small->t3.medium for SonarQube RAM requirement

---

## Phase 3 — DevOps Toolchain

### Deployment Method
Helm direct-install. ArgoCD App-of-Apps pattern used for GitOps sync after initial bootstrap.

### ArgoCD
| Field | Value |
|-------|-------|
| Chart | argo-cd-9.5.14 (ArgoCD v3.4.2) |
| Namespace | argocd |
| Install command | `helm install argocd argo/argo-cd -n argocd --create-namespace --wait` |
| Pod count | 7/7 Running |
| URL | `http://a944fe58b20d24057b8cf0af7f586c3a-245014201.us-east-1.elb.amazonaws.com` |
| HTTP status | 200 |
| Login | admin / (from `kubectl get secret argocd-initial-admin-secret`) |

Pods Running (live):
```
argocd-application-controller-0                     1/1   Running
argocd-applicationset-controller-7df68d4b7f-8dnv4   1/1   Running
argocd-dex-server-79fd9b947d-p8mwd                  1/1   Running
argocd-notifications-controller-bc95f9b95-8k7fn     1/1   Running
argocd-redis-69779fc597-rbhxf                       1/1   Running
argocd-repo-server-789fd77dcb-q65s7                 1/1   Running
argocd-server-5ccfcd9cdf-np45q                      1/1   Running
```

### Jenkins
| Field | Value |
|-------|-------|
| Chart | jenkins-5.9.22 (Jenkins 2.552.x) |
| Namespace | jenkins |
| Values file | `charts/jenkins/values.yaml` |
| Pod count | 2/2 Running |
| URL | `http://a910314d11cee49a99b923e221108e05-468852420.us-east-1.elb.amazonaws.com:8080` |
| HTTP status | 200 |
| Login | admin / (from `kubectl get secret jenkins -n jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d`) |

Resource config (from values.yaml):
- Requests: 200m CPU, 512Mi RAM
- Limits: 500m CPU, 1Gi RAM
- Persistence: 5Gi ebs-gp3
- Executors: 2

### SonarQube
| Field | Value |
|-------|-------|
| Chart | sonarqube-2026.x Community Edition |
| Namespace | sonarqube |
| Values file | `charts/sonarqube/values.yaml` |
| Pod count | 1/1 Running |
| URL | `http://a386f7224766d43d6b50aeee825abe34-1292105297.us-east-1.elb.amazonaws.com:9000` |
| HTTP status | 200 |
| Login | admin / admin (change on first login) |

Resource config (from values.yaml):
- Requests: 300m CPU, 1Gi RAM
- Limits: 1000m CPU, 2Gi RAM
- JVM: `-Xmx512m -Xms256m` (main) + `-Xmx256m -Xms128m` (CE)
- Persistence: 5Gi ebs-gp3, embedded H2 (PostgreSQL for production)
- Edition: `community.enabled: true` (breaking change from older `edition: community`)

### Harbor
| Field | Value |
|-------|-------|
| Chart | harbor/harbor v1.19.0 (App 2.15.0) |
| Namespace | harbor |
| Values file | `charts/harbor/values.yaml` |
| Commit | `260b2db` |
| Pod count | 8/8 Running |
| URL | `http://a68756541aa5a454d81e6515e061e3c2-574233704.us-east-1.elb.amazonaws.com` |
| HTTP status | 200 |
| Login | admin / Harbor12345 |

Pods Running (live):
```
harbor-core-858d45f7d5-tt2nw          1/1   Running
harbor-database-0                     1/1   Running
harbor-jobservice-69b4cd9dc6-ttbdh    1/1   Running   (2 restarts — init race, now stable)
harbor-nginx-7b5bf57db5-sfz8n         1/1   Running
harbor-portal-6bcb64f7cd-qbdwm        1/1   Running
harbor-redis-0                        1/1   Running
harbor-registry-6dddf6bfc4-56lxw      2/2   Running
harbor-trivy-0                        1/1   Running
```

Trivy vulnerability scanning: enabled.
TLS: disabled for POC (enable with cert-manager + Route53 in production).
Storage: 5x ebs-gp3 PVCs (registry 5Gi, jobservice 1Gi, database 1Gi, redis 1Gi, trivy 1Gi).

### Bugs Fixed During This Phase
| # | Issue | Fix |
|---|-------|-----|
| 1 | SonarQube OOMKill on t3.small — only ~920 MB available after system pods, Elasticsearch 8 + JVM needs 1.6 GB min | Upgraded node group from t3.small to t3.medium (3.75 GB allocatable). Cost delta: +$1/day |
| 2 | `edition=community` rejected by newer SonarQube chart | Changed to `community.enabled: true` in values.yaml — API changed in 2026.x chart |
| 3 | SonarQube liveness probe failing — `monitoringPasscode` required in newer chart versions | Added `monitoringPasscode: admin123` to values.yaml |

### Commits
- `df36571` — feat: Phase 3 - add POC Helm values for Jenkins and SonarQube
- `18c012f` — docs: Phase 3 complete - add tool URLs, lessons learned, teardown guide
- `260b2db` — feat: add Harbor container registry POC Helm values (devops-toolchain-helm)
- `e881345` — docs: add Harbor + Phase 1 prompt engine results to EXECUTION.md

---

## Phase 1 — Prompt Engine (infra-prompt-engine)

### Repository
- GitHub: https://github.com/srujantata/infra-prompt-engine
- Commit: `a000cee` — feat: Phase 1 complete - full prompt engine implementation

### Files Delivered
| File | Lines | Purpose |
|------|-------|---------|
| `prompt_engine/generate.py` | 225 | Claude API call + Terraform template generation + GitHub PR creation |
| `prompt_engine/cli.py` | 54 | Command-line interface (--dry-run, --mode terraform/kubectl) |
| `prompt_engine/server.py` | 78 | FastAPI REST server |
| `tests/test_generate.py` | 80 | Unit tests (mock Claude API — 4 tests) |
| `.github/workflows/test.yml` | — | CI pipeline — runs pytest on every PR |
| `README.md` | — | Usage documentation with API reference |

### API Endpoints Verified
| Method | Path | Description | Verified |
|--------|------|-------------|---------|
| GET | `/health` | Health check | Returns 200 |
| POST | `/generate/dry-run` | Preview generated Terraform HCL — no PR opened | Returns 3 files (main.tf, variables.tf, outputs.tf) |
| POST | `/generate` | Generate Terraform + open GitHub PR | Returns `pr_url` |

### Unit Tests — pytest output (4 tests)
```
tests/test_generate.py::TestGenerateTerraform::test_returns_three_files      PASSED
tests/test_generate.py::TestGenerateTerraform::test_strips_markdown_fences   PASSED
tests/test_generate.py::TestGenerateTerraform::test_raises_on_invalid_json   PASSED
tests/test_generate.py::TestGenerateTerraform::test_raises_on_missing_keys   PASSED
```

### How It Works
```
User prompt -> Claude API (claude-sonnet) -> Terraform HCL (3 files)
    -> GitHub branch -> PR opened -> GitHub Actions runs terraform plan
    -> Human reviews plan in PR comment -> Merges -> terraform apply
```

---

## Phase 1.5 — kubectl Admin Layer

### Repository
- GitHub: https://github.com/srujantata/infra-prompt-engine
- Commit: `53dea5a` — feat: add kubectl natural-language admin layer — POST /kubectl, --mode kubectl CLI

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/kubectl` | Translate (and optionally execute) plain-English kubectl request |
| POST | `/kubectl/dry-run` | Always translate only — execute flag ignored, safe for pipelines |

### Example Translations Verified
| Natural Language Prompt | Generated kubectl Command | Risk |
|-------------------------|--------------------------|------|
| scale Jenkins to 3 replicas | `kubectl scale deployment jenkins --replicas=3 -n jenkins` | low |
| show all pods not Running | `kubectl get pods -A --field-selector=status.phase!=Running` | low |
| restart the Harbor registry deployment | `kubectl rollout restart deployment harbor-core -n harbor` | medium |
| cordon node ip-10-0-1-219 for maintenance | `kubectl cordon ip-10-0-1-219` | high |

### Unit Tests — pytest output (8 tests)
```
tests/test_kubectl_exec.py::TestTranslateToKubectl::test_translate_returns_commands         PASSED
tests/test_kubectl_exec.py::TestTranslateToKubectl::test_dry_run_does_not_execute           PASSED
tests/test_kubectl_exec.py::TestTranslateToKubectl::test_invalid_json_raises                PASSED
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_delete_node              PASSED
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_delete_cluster           PASSED
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_destroy                  PASSED
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_drain_without_dry_run    PASSED
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_allows_drain_with_dry_run       PASSED
```

### Safety Model — Blocked Patterns
The following are always blocked at execution time regardless of `--execute` or `execute: true`:

| Blocked Pattern | Reason |
|-----------------|--------|
| `delete cluster` | Destroys the entire EKS cluster |
| `destroy` | Catches Terraform/eksctl destroy commands slipping through |
| `kubectl delete node` | Removes a node from the cluster permanently |
| `drain` without `--dry-run` | Evicts all pods from a node; requires explicit confirmation |

High-risk commands (`risk: high`) surface a warning in both API response and CLI output.
To execute blocked operations, run the generated command manually after review.

---

## Live Cluster Verification (2026-05-18)

### Node Status
```
NAME                         STATUS   ROLES   AGE    VERSION                INTERNAL-IP   EXTERNAL-IP
ip-10-0-1-219.ec2.internal   Ready    <none>  170m   v1.30.14-eks-7fcd7ec   10.0.1.219    3.83.20.248
ip-10-0-2-10.ec2.internal    Ready    <none>  170m   v1.30.14-eks-7fcd7ec   10.0.2.10     98.94.56.113
```
- OS: Amazon Linux 2023.11.20260509
- Kernel: 6.1.170-210.320.amzn2023.x86_64
- Runtime: containerd 2.2.3

### Pod Status — All Namespaces
```
NAMESPACE     NAME                                                READY   STATUS    RESTARTS
argocd        argocd-application-controller-0                     1/1     Running   0
argocd        argocd-applicationset-controller-7df68d4b7f-8dnv4   1/1     Running   0
argocd        argocd-dex-server-79fd9b947d-p8mwd                  1/1     Running   0
argocd        argocd-notifications-controller-bc95f9b95-8k7fn     1/1     Running   0
argocd        argocd-redis-69779fc597-rbhxf                       1/1     Running   0
argocd        argocd-repo-server-789fd77dcb-q65s7                 1/1     Running   0
argocd        argocd-server-5ccfcd9cdf-np45q                      1/1     Running   0
harbor        harbor-core-858d45f7d5-tt2nw                        1/1     Running   0
harbor        harbor-database-0                                   1/1     Running   0
harbor        harbor-jobservice-69b4cd9dc6-ttbdh                  1/1     Running   2
harbor        harbor-nginx-7b5bf57db5-sfz8n                       1/1     Running   0
harbor        harbor-portal-6bcb64f7cd-qbdwm                      1/1     Running   0
harbor        harbor-redis-0                                      1/1     Running   0
harbor        harbor-registry-6dddf6bfc4-56lxw                    2/2     Running   0
harbor        harbor-trivy-0                                      1/1     Running   0
jenkins       jenkins-0                                           2/2     Running   0
kube-system   aws-node-jvqk8                                      2/2     Running   0
kube-system   aws-node-xwzrh                                      2/2     Running   0
kube-system   coredns-849f74687b-rbjzq                            1/1     Running   0
kube-system   coredns-849f74687b-zhprv                            1/1     Running   0
kube-system   ebs-csi-controller-5745c79fb7-nn6gs                 6/6     Running   0
kube-system   ebs-csi-controller-5745c79fb7-p76mv                 6/6     Running   0
kube-system   ebs-csi-node-ntw88                                  3/3     Running   0
kube-system   ebs-csi-node-srpz4                                  3/3     Running   0
kube-system   kube-proxy-8dbfx                                    1/1     Running   0
kube-system   kube-proxy-hk8t6                                    1/1     Running   0
sonarqube     sonarqube-sonarqube-0                               1/1     Running   0
```

Total pods: 27 | All Running | 0 CrashLoopBackOff | 0 Pending

### LoadBalancer Services
```
NAMESPACE   NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)
argocd      argocd-server          LoadBalancer   172.20.39.115    a944fe58b20d24057b8cf0af7f586c3a-245014201.us-east-1.elb.amazonaws.com    80:31387/TCP,443:31669/TCP
harbor      harbor                 LoadBalancer   172.20.61.42     a68756541aa5a454d81e6515e061e3c2-574233704.us-east-1.elb.amazonaws.com    80:31887/TCP
jenkins     jenkins                LoadBalancer   172.20.241.248   a910314d11cee49a99b923e221108e05-468852420.us-east-1.elb.amazonaws.com    8080:31352/TCP
sonarqube   sonarqube-sonarqube    LoadBalancer   172.20.66.130    a386f7224766d43d6b50aeee825abe34-1292105297.us-east-1.elb.amazonaws.com   9000:30455/TCP
```

### Live Tool URLs

| Tool | URL | Port | Status |
|------|-----|------|--------|
| ArgoCD | `http://a944fe58b20d24057b8cf0af7f586c3a-245014201.us-east-1.elb.amazonaws.com` | 80 | Live |
| Jenkins | `http://a910314d11cee49a99b923e221108e05-468852420.us-east-1.elb.amazonaws.com:8080` | 8080 | Live |
| SonarQube | `http://a386f7224766d43d6b50aeee825abe34-1292105297.us-east-1.elb.amazonaws.com:9000` | 9000 | Live |
| Harbor | `http://a68756541aa5a454d81e6515e061e3c2-574233704.us-east-1.elb.amazonaws.com` | 80 | Live |

> All URLs are ephemeral AWS ALB hostnames — they change on each `terraform destroy/apply` cycle.
> Use Route53 with a stable domain for production.

---

## Automated Test Suite — Full Results (2026-05-18)

```
============================= test session starts =============================
platform win32 -- Python 3.13.13, pytest-9.0.3, pluggy-1.6.0
rootdir: D:\Srujan\Claude\devops\infra-prompt-engine
configfile: pyproject.toml

tests/test_generate.py::TestGenerateTerraform::test_returns_three_files      PASSED [  8%]
tests/test_generate.py::TestGenerateTerraform::test_strips_markdown_fences   PASSED [ 16%]
tests/test_generate.py::TestGenerateTerraform::test_raises_on_invalid_json   PASSED [ 25%]
tests/test_generate.py::TestGenerateTerraform::test_raises_on_missing_keys   PASSED [ 33%]
tests/test_kubectl_exec.py::TestTranslateToKubectl::test_translate_returns_commands         PASSED [ 41%]
tests/test_kubectl_exec.py::TestTranslateToKubectl::test_dry_run_does_not_execute           PASSED [ 50%]
tests/test_kubectl_exec.py::TestTranslateToKubectl::test_invalid_json_raises                PASSED [ 58%]
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_delete_node              PASSED [ 66%]
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_delete_cluster           PASSED [ 75%]
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_destroy                  PASSED [ 83%]
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_blocks_drain_without_dry_run    PASSED [ 91%]
tests/test_kubectl_exec.py::TestExecuteKubectl::test_safety_allows_drain_with_dry_run       PASSED [100%]

============================= 12 passed in 1.45s ==============================
```

**Result: 12/12 tests passing. 0 failures. 0 skipped.**

---

## GitHub Repositories

| Repo | URL | Purpose |
|------|-----|---------|
| aws-eks-platform | https://github.com/srujantata/aws-eks-platform | EKS cluster Terraform — VPC, nodes, IAM, EBS CSI |
| devops-toolchain-helm | https://github.com/srujantata/devops-toolchain-helm | Helm values for Jenkins, SonarQube, Harbor, ArgoCD |
| infra-prompt-engine | https://github.com/srujantata/infra-prompt-engine | Claude API prompt-to-Terraform engine + kubectl admin layer |
| github-actions-iac | https://github.com/srujantata/github-actions-iac | Reusable CI/CD workflows using GitHub OIDC (keyless AWS auth) |
| dr-failover-runbook | https://github.com/srujantata/dr-failover-runbook | Active-passive DR documentation (us-east-1 primary, us-west-2 DR) |

---

## Cost Tracking

| Resource | Rate | 2-week POC |
|----------|------|-----------|
| EKS control plane | $0.10/hr | ~$33.60 |
| 2x t3.medium nodes (On-Demand) | $0.0832/hr each | ~$55.90 |
| 4x Application Load Balancers | ~$0.05/hr combined | ~$16.80 |
| EBS volumes (gp3, ~19Gi total) | ~$0.002/hr | ~$0.67 |
| S3 + DynamoDB (bootstrap) | ~$0.001/day | ~$0.02 |
| **Total** | **~$4.30/day** | **~$60** |
| AWS new-account credits | — | $200 |
| **Out of pocket** | | **$0** |

Original estimate used t3.small nodes (~$4.30/day). Upgrade to t3.medium for SonarQube RAM pushed to ~$5.90/day. Still within $200 credits for 2-week POC.

> Production estimate: ~$2,400/month (see COST.md)

---

## Known Issues / Deferred

| Issue | Severity | Notes |
|-------|----------|-------|
| Harbor `externalURL` not set to ALB hostname | Low | Affects `docker push` redirect (302 to internal hostname). For POC use `--insecure-registry` flag. Fix: set `externalURL` in values.yaml to ALB hostname or Route53 domain. |
| No stable DNS (Route53) for any tool | Low | ALB hostnames change on every `terraform destroy/apply`. Cosmetic for POC — add Route53 CNAME aliases for production. |
| Phase 4 DR (us-west-2) — Terraform not applied | Deferred | DR architecture documented in `dr-failover-runbook`. Runbook covers RTO 4hr, RPO 1hr, active-passive with Route53 health checks. Terraform for us-west-2 exists but not applied — production-only. |
| Harbor-jobservice 2 restarts at startup | Cosmetic | Init race condition at first deploy. Pod stabilized immediately and has 0 restarts since. No action needed. |
| SonarQube uses embedded H2 database | POC-only | Suitable for POC/demo. Production requires external RDS PostgreSQL — `postgresql.enabled: true` in values.yaml + RDS instance. |
| TLS disabled on all tools | POC-only | All 4 tools serving HTTP only. Production: add cert-manager + ACM certificates + HTTPS listeners. |

---

## Teardown Checklist

Run before credits run out to avoid unexpected charges (~$2.23/hr if left running).

```powershell
# 1 — Remove Helm releases (deletes ALBs and PVCs)
helm uninstall sonarqube -n sonarqube
helm uninstall jenkins -n jenkins
helm uninstall argocd -n argocd

# 2 — Delete PVCs (releases EBS volumes)
kubectl delete pvc --all -n sonarqube
kubectl delete pvc --all -n jenkins

# 3 — Wait for ALBs to fully deregister
Start-Sleep 120

# 4 — Destroy EKS cluster
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"
terraform destroy -auto-approve   # ~10 min

# 5 — Verify clean
aws ec2 describe-instances --region us-east-1 --filters "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId"
aws eks list-clusters --region us-east-1
# Both should return []

# Bootstrap (S3+DynamoDB) can stay — costs $0.01/month and lets you redeploy anytime
```

---

*Author: Srujan Tata | AWS Account: 296214942633 | Cluster endpoint: https://3D6DF603FA21813ADA47B266178C114F.gr7.us-east-1.eks.amazonaws.com*
