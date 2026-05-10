output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region us-east-1"
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "monthly_cost_estimate" {
  description = "Rough monthly cost breakdown"
  value       = <<-EOT
    EKS Control Plane:     $72.00
    2x t3.small On-Demand: $25.18
    EBS (50Gi total):       $5.00
    S3 (state):             $0.50
    ALB (1x):              $16.00
    Data transfer:          ~$2.00
    ─────────────────────────────
    TOTAL/month:          ~$120.68
    2-week POC total:      ~$60
  EOT
}
