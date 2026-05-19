# aws-eks-platform

![Terraform](https://img.shields.io/badge/Terraform-1.8-7B42BC?logo=terraform)
![EKS](https://img.shields.io/badge/EKS-1.30-FF9900?logo=amazon-aws)
![License](https://img.shields.io/badge/license-MIT-blue)

Production-grade EKS cluster for a DevOps toolchain — deployed via Terraform, GitOps-managed by ArgoCD. Documented with both POC (cost-minimal) and Production (HA + active-passive DR) configurations.

## Configurations

| | POC | Production |
|--|-----|------------|
| **Purpose** | Skill demo, ~2 weeks | Long-running, HA |
| **AZs** | 1 (us-east-1a) | 3 (us-east-1a/b/c) |
| **Nodes** | 2× t3.small | 6× m5.2xlarge |
| **NAT Gateway** | None (public subnets) | 1 per AZ |
| **Database** | In-cluster PostgreSQL | Aurora Global DB |
| **Storage** | EBS gp3 | EBS + EFS |
| **DR** | None | Active-passive us-west-2 |
| **Est. cost** | ~$60/2 weeks | ~$2,100/month |

## Architecture (POC)

```
VPC (10.0.0.0/16) — Single AZ: us-east-1a
└── Public Subnet (10.0.1.0/24)
    └── EKS 1.30 (terraform-aws-modules/eks v20)
        ├── 2× t3.small nodes (On-Demand)
        └── Add-ons: EBS CSI | CoreDNS | kube-proxy | VPC-CNI
            └── ArgoCD (App-of-Apps)
                ├── Jenkins
                ├── SonarQube Community
                └── Harbor
```

## Quick Start (POC)

### Prerequisites
```bash
# Install tools
winget install Hashicorp.Terraform Amazon.AWSCLI GitHub.cli

# Configure credentials
aws configure        # enter your AWS keys
gh auth login        # browser login
```

### Phase 0 — Bootstrap (run once)
```bash
cd terraform/global
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set github_org = "srujantata"
terraform init && terraform apply
```

### Deploy POC cluster
```bash
cd terraform/environments/poc
# Edit main.tf: replace REPLACE_WITH_STATE_BUCKET with output from Phase 0
terraform init && terraform plan && terraform apply
aws eks update-kubeconfig --name devops-poc --region us-east-1
kubectl get nodes   # should show 2 nodes
```

### Destroy when done (stop billing)
```powershell
# Windows
$env:TF_STATE_BUCKET = "devops-tfstate-YOUR_ACCOUNT_ID"
.\scripts\destroy-all.ps1
```

See [COST.md](COST.md) for full cost breakdown and billing alerts.

## AI Administration Layer

The cluster is administered through natural language via the [infra-prompt-engine](https://github.com/srujantata/infra-prompt-engine).

### What it does

| Capability | API | Example |
|------------|-----|---------|
| Terraform generation | `POST /generate` | "Create a VPC with 3 AZs and NAT gateway" → opens GitHub PR |
| kubectl natural language | `POST /kubectl` | "scale Jenkins to 3 replicas" → translates + optionally executes |
| Dry-run preview | `POST /generate/dry-run` | Returns generated HCL without writing files or opening a PR |

### Chat UI

A single-file Progressive Web App (PWA) ships with the prompt engine at `chat_ui/index.html`:

- Dark theme with sidebar showing live cluster health, ArgoCD/Jenkins/SonarQube/Harbor quick-links
- Chat bubbles with syntax-highlighted kubectl commands and collapsible execution results
- Execute toggle (off by default — safe translate-only mode); red warning banner when execute is on
- Installable on phone via "Add to Home Screen" — works on the same WiFi as your PC

**Start the chat UI:**
```powershell
cd D:\Srujan\Claude\devops\infra-prompt-engine
uvicorn prompt_engine.server:app --host 0.0.0.0 --port 8000
python -m http.server 3000 --directory chat_ui
# Open http://localhost:3000
```

### Local AI (Ollama — zero API cost)

Swap the Anthropic backend for a locally-running `codellama:34b` on your RTX 4090 — all inference stays on-machine, no API calls, $0/month after setup.

Full setup guide: [infra-prompt-engine/LOCAL_AI_SETUP.md](https://github.com/srujantata/infra-prompt-engine/blob/master/LOCAL_AI_SETUP.md)

```powershell
[System.Environment]::SetEnvironmentVariable("INFRA_AI_BACKEND","ollama","User")
[System.Environment]::SetEnvironmentVariable("INFRA_AI_MODEL","codellama:34b","User")
[System.Environment]::SetEnvironmentVariable("INFRA_AI_BASE_URL","http://localhost:11434","User")
```

### Roadmap

The prompt engine is Phase 1 of a planned autonomous DevOps platform — self-healing loops, AI-driven CVE patching, Prometheus alert responder, cost analyser, and DR activation via conversation. See [infra-prompt-engine/ROADMAP.md](https://github.com/srujantata/infra-prompt-engine/blob/master/ROADMAP.md) for the full 7-phase vision.

---

## Skills Demonstrated

`Terraform` · `AWS EKS` · `VPC networking` · `ArgoCD` · `IRSA` · `GitOps` · `GitHub Actions` · `OIDC` · `HA/DR architecture` · `Cost optimisation` · `Claude API` · `kubectl natural language` · `PWA`
