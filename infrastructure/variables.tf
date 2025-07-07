variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "proxy_cluster_name" {
  description = "Name of the proxy ECS cluster"
  type        = string
  default     = "proxy-cluster"
}

variable "web_cluster_name" {
  description = "Name of the web ECS cluster"
  type        = string
  default     = "web-cluster"
}

variable "proxy_instance_type" {
  description = "EC2 instance type for proxy cluster"
  type        = string
  default     = "t3.medium"
}

variable "sites" {
  description = "List of site configurations"
  type = list(object({
    name        = string
    domain      = string
    environment = string
  }))
  default = [
    {
      name        = "site1"
      domain      = "example1.com"
      environment = "production"
    },
    {
      name        = "site2"
      domain      = "example2.com"
      environment = "staging"
    }
  ]
}

variable "db_host" {
  description = "Database host for Lambda functions"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name for Lambda functions"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}