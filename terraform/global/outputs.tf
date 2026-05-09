output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.tflock.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider — use in IAM trust policies"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "backend_config_snippet" {
  description = "Paste this into terraform {} block in every other environment"
  value = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.tfstate.id}"
      key            = "ENV/terraform.tfstate"   # replace ENV
      region         = "${var.primary_region}"
      encrypt        = true
      dynamodb_table = "${aws_dynamodb_table.tflock.name}"
    }
  EOT
}
