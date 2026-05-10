#!/usr/bin/env bash
# ============================================================
# DESTROY ALL — POC Teardown Script
# Removes ALL AWS resources created for the devops-poc project.
# Run this when the POC is complete to stop all billing.
# ============================================================
set -euo pipefail

CLUSTER_NAME="devops-poc"
REGION="us-east-1"
STATE_BUCKET="${TF_STATE_BUCKET:-REPLACE_WITH_YOUR_BUCKET}"

echo "======================================================"
echo " DevOps POC — DESTROY ALL AWS RESOURCES"
echo " Cluster: $CLUSTER_NAME | Region: $REGION"
echo "======================================================"
echo ""
echo "WARNING: This will permanently delete:"
echo "  - EKS cluster '$CLUSTER_NAME' and all nodes"
echo "  - VPC, subnets, security groups"
echo "  - All EBS volumes (Jenkins, SonarQube, Harbor data)"
echo "  - ALB load balancers"
echo "  - IAM roles created by Terraform"
echo ""
read -rp "Type 'destroy' to confirm: " confirm
if [[ "$confirm" != "destroy" ]]; then
  echo "Cancelled."
  exit 1
fi

echo ""
echo "Step 1/4 — Removing ArgoCD apps (so it stops recreating resources)..."
kubectl delete applications --all -n argocd --ignore-not-found=true 2>/dev/null || true
kubectl delete appprojects --all -n argocd --ignore-not-found=true 2>/dev/null || true
sleep 10

echo ""
echo "Step 2/4 — Deleting Helm releases (Jenkins, SonarQube, Harbor, ArgoCD)..."
for ns in jenkins sonarqube harbor argocd; do
  helm list -n "$ns" -q 2>/dev/null | xargs -r helm uninstall -n "$ns" 2>/dev/null || true
done
sleep 15

echo ""
echo "Step 3/4 — Deleting any remaining LoadBalancer services (removes AWS ALBs)..."
kubectl get svc --all-namespaces -o json 2>/dev/null \
  | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
  | xargs -r -L1 bash -c 'kubectl delete svc $2 -n $1' _ || true
sleep 30   # Wait for AWS to clean up ELBs before VPC delete

echo ""
echo "Step 4/4 — Terraform destroy (EKS, VPC, all networking)..."
cd "$(dirname "$0")/../terraform/environments/poc"
terraform init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=poc/terraform.tfstate" \
  -backend-config="region=$REGION"
terraform destroy -auto-approve

echo ""
echo "======================================================"
echo " ALL RESOURCES DESTROYED. Billing has stopped."
echo ""
echo " Optional cleanup (run manually if desired):"
echo "   - Delete S3 state bucket: aws s3 rb s3://$STATE_BUCKET --force"
echo "   - Delete DynamoDB lock table: aws dynamodb delete-table --table-name terraform-lock"
echo "   - Remove GitHub OIDC provider from AWS IAM console"
echo "======================================================"
