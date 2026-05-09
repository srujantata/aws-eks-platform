variable "primary_region" {
  description = "AWS primary region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS DR region (active-passive standby)"
  type        = string
  default     = "us-west-2"
}

variable "github_org" {
  description = "GitHub org or username that owns the repos (used in OIDC trust)"
  type        = string
  # Set via terraform.tfvars or TF_VAR_github_org env var
}

variable "tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "devops-platform"
    ManagedBy   = "terraform"
    Environment = "global"
    Owner       = "srujantata"
  }
}
