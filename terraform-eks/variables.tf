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
  description = "EC2 instance types for the managed node group. t3.small. Started on t3.micro for free-tier eligibility, but 1GB per node (~520Mi allocatable) could not hold WildFly plus an Envoy sidecar - the app was evicted repeatedly and the WildFly 40 upgrade made it unschedulable entirely. Three t3.small nodes cost roughly the same as five micros and leave real headroom."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}