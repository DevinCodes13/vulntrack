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
  default     = "vulntrack"
}

variable "container_image" {
  description = "Full ECR image URI, including tag (e.g. <acct>.dkr.ecr.us-east-2.amazonaws.com/vulntrack:latest)"
  type        = string
}

variable "container_port" {
  description = "Port the WildFly container listens on"
  type        = number
  default     = 8080
}

variable "db_name" {
  description = "Postgres database name"
  type        = string
  default     = "vulntrack"
}

variable "db_username" {
  description = "Postgres master username"
  type        = string
  default     = "vulntrack"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}
