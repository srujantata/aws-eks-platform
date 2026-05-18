# Bootstrap: Terraform state backend, GitHub OIDC, IAM Role
# Run this ONCE manually before using remote state anywhere else.
# Usage: terraform init && terraform apply

terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state for the bootstrap itself (chicken-and-egg)
  # After apply, state file lives locally — back it up.
}

provider "aws" {
  region = var.primary_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────
# S3 — Terraform Remote State Bucket
# ─────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket        = "devops-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────
# DynamoDB — Terraform State Locking
# ─────────────────────────────────────────
resource "aws_dynamodb_table" "tflock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

# ─────────────────────────────────────────
# GitHub OIDC — Keyless Auth for Actions
# ─────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable; verify at https://token.actions.githubusercontent.com)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

# ─────────────────────────────────────────
# IAM Role — GitHub Actions assume role
# ─────────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name        = "GitHubActionsRole"
  description = "Assumed by GitHub Actions via OIDC - no long-lived keys"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Scope to your GitHub org — replace YOUR_GITHUB_ORG
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/*:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Grant AdministratorAccess (scope down per-workflow later via SCPs or per-repo roles)
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ─────────────────────────────────────────
# State backend policy — scoped to tfstate bucket
# ─────────────────────────────────────────
resource "aws_iam_policy" "tfstate_access" {
  name        = "TerraformStateAccess"
  description = "Allow read/write to Terraform state S3 bucket and DynamoDB lock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3State"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
      },
      {
        Sid    = "DynamoLock"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.tflock.arn
      }
    ]
  })
}
