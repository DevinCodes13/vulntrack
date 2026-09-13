variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Local AWS CLI profile Terraform uses to authenticate"
  type        = string
  default     = "vulntrack-terraform"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "vulntrack-eks"
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC (deliberately separate range from the ECS VPC's 10.0.0.0/16)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane. Verify this is still supported in the AWS Console before applying — EKS deprecates old versions on a rolling basis."
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group. t3.micro chosen specifically because this AWS account is Free-Tier-restricted to only free-tier-eligible instance types; note this gives only 1GB RAM per node, which may be tight once Istio sidecars are injected alongside WildFly."
  type        = list(string)
  default     = ["t3.micro"]
}

variable "node_desired_size" {
  type    = number
  default = 5
}

variable "node_min_size" {
  type    = number
  default = 4
}

variable "node_max_size" {
  type    = number
  default = 5
}