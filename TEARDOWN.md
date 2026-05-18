# Teardown Guide — Destroy All Infrastructure

⚠️ Run this when done with the POC to stop all AWS charges.

## Cost if left running
- t3.medium × 2: $0.0832/hr = ~$2/hr
- EKS control plane: $0.10/hr
- ALBs (3×): ~$0.05/hr
- **Total: ~$2.23/hr = ~$53/day**

## Teardown Order (MUST follow — wrong order leaves orphaned LBs charging you)

### Step 1 — Delete Kubernetes apps (removes ALBs and PVCs)
```powershell
# Uninstall all Helm releases
helm uninstall sonarqube -n sonarqube
helm uninstall jenkins -n jenkins
helm uninstall argocd -n argocd

# Delete PVCs (releases EBS volumes)
kubectl delete pvc --all -n sonarqube
kubectl delete pvc --all -n jenkins

# Wait for ALBs to fully deregister (~2 min)
Start-Sleep 120
```

### Step 2 — Verify ALBs are gone
```powershell
& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" elb describe-load-balancers --region us-east-1 --query "LoadBalancerDescriptions[].LoadBalancerName"
& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[].LoadBalancerArn"
# Both should return empty arrays []
```

### Step 3 — Destroy EKS cluster
```powershell
$tf = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Filter "terraform.exe" -Recurse | Select -First 1).FullName
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"
& $tf destroy -auto-approve
# Takes ~10 minutes
```

### Step 4 — Verify EC2 instances terminated
```powershell
& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ec2 describe-instances --region us-east-1 `
  --filters "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[].InstanceId"
# Should return []

& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" eks list-clusters --region us-east-1
# Should return {"clusters": []}
```

### Step 5 (Optional) — Destroy bootstrap
Keep the bootstrap (S3 + DynamoDB + OIDC) — it costs ~$0.01/month and lets you redeploy anytime.

To destroy everything:
```powershell
Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\global"
& $tf destroy -auto-approve
```

## Quick one-liner (if you trust it)
```powershell
# WARNING: destroys everything without confirmation
helm uninstall sonarqube -n sonarqube; helm uninstall jenkins -n jenkins; helm uninstall argocd -n argocd; kubectl delete pvc --all -n sonarqube; kubectl delete pvc --all -n jenkins; Start-Sleep 120; Set-Location "D:\Srujan\Claude\devops\aws-eks-platform\terraform\environments\poc"; & $tf destroy -auto-approve
```
