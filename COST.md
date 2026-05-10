# Cost Guide — POC vs Production

## POC Configuration (what's deployed here)

> Goal: demonstrate skills at minimum cost. Run for 2 weeks, then destroy.

| Resource | Spec | $/month | $/2 weeks |
|----------|------|---------|-----------|
| EKS Control Plane | 1 cluster | $72.00 | $36.00 |
| EC2 Nodes | 2× t3.small On-Demand | $25.18 | $12.59 |
| EBS Volumes | 50Gi gp3 total | $5.00 | $2.50 |
| S3 (state) | < 1GB | $0.50 | $0.25 |
| ALB | 1× (Jenkins ingress) | $16.00 | $8.00 |
| Data transfer | Minimal POC usage | ~$2.00 | ~$1.00 |
| **POC TOTAL** | | **~$120** | **~$60** |

> No NAT Gateway (saves $32/month), no RDS (saves $30/month), no EFS (saves $30/month), no DR cluster (saves $120/month).

## Cost Guardrails

Set these billing alerts in AWS console immediately after account creation:

| Alert | Threshold | Action |
|-------|-----------|--------|
| Budget alert 1 | $30 | Email warning |
| Budget alert 2 | $60 | Email warning |
| Budget alert 3 | $100 | Email + consider destroy |

```bash
# Create $100 budget alert via CLI
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "poc-limit",
    "BudgetLimit": {"Amount": "100", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{"SubscriptionType": "EMAIL","Address": "tatasrujan@gmail.com"}]
  }]'
```

## Destroy When Done

```bash
# Linux/Mac
export TF_STATE_BUCKET="devops-tfstate-YOUR_ACCOUNT_ID"
bash scripts/destroy-all.sh

# Windows PowerShell
$env:TF_STATE_BUCKET = "devops-tfstate-YOUR_ACCOUNT_ID"
.\scripts\destroy-all.ps1
```

## Production Configuration (documented, not deployed)

| Resource | Spec | $/month |
|----------|------|---------|
| EKS (primary + DR) | 2 clusters | $144 |
| EC2 Nodes | 6× m5.2xlarge On-Demand | $1,040 |
| Karpenter Spot pool | ~4× m5.xlarge avg | $120 |
| Aurora Global DB | Writer + 2 RR + DR | $330 |
| EFS | 500Gi multi-AZ | $150 |
| NAT Gateways | 3× primary, 2× DR | $175 |
| S3, ALBs, monitoring | Various | $170 |
| **Production TOTAL** | | **~$2,129** |
