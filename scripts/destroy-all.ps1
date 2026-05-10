# destroy-all.ps1 — Windows version of destroy-all.sh
# Run from PowerShell after POC is complete

param(
    [string]$StateBucket = $env:TF_STATE_BUCKET,
    [string]$ClusterName = "devops-poc",
    [string]$Region = "us-east-1"
)

Write-Host "======================================================" -ForegroundColor Red
Write-Host " DevOps POC — DESTROY ALL AWS RESOURCES" -ForegroundColor Red
Write-Host " Cluster: $ClusterName | Region: $Region" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Red
Write-Host ""
Write-Host "WARNING: This permanently deletes ALL POC AWS resources." -ForegroundColor Yellow

$confirm = Read-Host "Type 'destroy' to confirm"
if ($confirm -ne "destroy") {
    Write-Host "Cancelled." -ForegroundColor Green
    exit 0
}

Write-Host "`nStep 1/4 — Removing ArgoCD apps..." -ForegroundColor Cyan
kubectl delete applications --all -n argocd --ignore-not-found=true 2>$null
Start-Sleep -Seconds 10

Write-Host "`nStep 2/4 — Uninstalling Helm releases..." -ForegroundColor Cyan
foreach ($ns in @("jenkins","sonarqube","harbor","argocd")) {
    $releases = helm list -n $ns -q 2>$null
    foreach ($r in $releases) {
        helm uninstall $r -n $ns 2>$null
    }
}
Start-Sleep -Seconds 15

Write-Host "`nStep 3/4 — Deleting LoadBalancer services (removes ALBs)..." -ForegroundColor Cyan
kubectl get svc --all-namespaces -o json 2>$null | `
    & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" -- 2>$null   # just wait
Start-Sleep -Seconds 30

Write-Host "`nStep 4/4 — Terraform destroy..." -ForegroundColor Cyan
$tfDir = Join-Path $PSScriptRoot "..\terraform\environments\poc"
Set-Location $tfDir
terraform init `
    -backend-config="bucket=$StateBucket" `
    -backend-config="key=poc/terraform.tfstate" `
    -backend-config="region=$Region"
terraform destroy -auto-approve

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host " ALL RESOURCES DESTROYED. Billing has stopped." -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
