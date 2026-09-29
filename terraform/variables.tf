variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Must be staging or production."
  }
}

variable "cluster_name" {
  type    = string
  default = "eks-gitops"
}

variable "cluster_version" {
  type    = string
  default = "1.31"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "system_node_instance" {
  description = "Instance type for system node group (ArgoCD, Prometheus, etc.)"
  type        = string
  default     = "t3.medium"
}

variable "app_node_instance" {
  description = "Instance type for application node group"
  type        = string
  default     = "t3.large"
}

variable "app_node_min" { type = number; default = 2 }
variable "app_node_max" { type = number; default = 10 }

variable "github_repo" {
  description = "GitHub repo that ArgoCD watches (org/repo)"
  type        = string
}
