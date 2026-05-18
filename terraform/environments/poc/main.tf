# POC Environment — Minimal cost, single-AZ, public subnets, no NAT Gateway
# Estimated cost: ~$97/month (EKS $72 + 2×t3.small $25)
# Run for 2 weeks ≈ $48 total. Destroy when done.

terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "devops-tfstate-296214942633"
    key            = "poc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = "us-east-1"
}

# Kubernetes provider — authenticates via AWS EKS token (requires cluster to exist first)
# Use: terraform apply -target=module.eks before full apply
provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", "us-east-1"]
  }
}

locals {
  cluster_name = "devops-poc"
  # EKS requires subnets in at least 2 AZs — use minimal 2-AZ spread
  azs = ["us-east-1a", "us-east-1b"]
  tags = {
    Project     = "devops-platform"
    Environment = "poc"
    ManagedBy   = "terraform"
    Owner       = "srujantata"
    CostCenter  = "poc-demo"
  }
}

# ─────────────────────────────────────────
# VPC — Two AZs (EKS requirement), public subnets only (no NAT Gateway = saves $32/month)
# ─────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs            = local.azs
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Auto-assign public IPs so nodes can reach internet without NAT
  map_public_ip_on_launch = true

  # No private subnets, no NAT gateway — POC cost saving
  enable_nat_gateway = false
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for EKS load balancer discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                          = "1"
    "kubernetes.io/cluster/${local.cluster_name}"     = "owned"
  }

  tags = local.tags
}

# ─────────────────────────────────────────
# EKS Cluster — Minimal single-AZ config
# ─────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets   # Public subnets (no NAT needed)

  # Allow public API access (POC convenience — restrict in production)
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  enable_irsa = true

  # Minimal managed node group — 2× t3.small
  # t3.small: 2 vCPU, 2GB RAM — enough for Jenkins + SonarQube + Harbor
  eks_managed_node_groups = {
    poc_nodes = {
      instance_types = ["t3.small"]
      min_size       = 2
      max_size       = 3         # Allow one extra for rolling updates
      desired_size   = 2
      capacity_type  = "ON_DEMAND"   # More reliable than Spot for demo

      # Nodes in public subnet (POC only — no NAT required)
      subnet_ids = module.vpc.public_subnets

      labels = {
        role = "poc-workload"
      }

      # EBS CSI driver requires EC2 permissions on the node role (POC — no IRSA needed)
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }

  # EKS Add-ons (minimal set)
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  tags = local.tags
}

# ─────────────────────────────────────────
# EBS StorageClass — gp3 (faster + cheaper than gp2)
# ─────────────────────────────────────────
resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type       = "gp3"
    encrypted  = "true"
    iops       = "3000"
    throughput = "125"
  }

  depends_on = [module.eks]
}
