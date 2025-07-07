variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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
  description = "EC2 instance type for proxy"
  type        = string
  default     = "t3.micro"
}

variable "vpc_id" {
  description = "VPC id"
  type        = string
}

variable "proxy_subnet_ids" {
  description = "Subnets for proxy cluster"
  type        = list(string)
}

variable "web_subnet_ids" {
  description = "Subnets for web cluster"
  type        = list(string)
}

variable "sites" {
  description = "List of site configurations"
  type = list(object({
    name            = string
    bucket_name     = string
    lambda_handler  = string
    lambda_runtime  = string
    secret_arn      = string
  }))
  default = []
}
