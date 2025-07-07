terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Proxy ECS cluster with EC2 instance running Traefik
module "proxy_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"

  cluster_name = var.proxy_cluster_name

  create_cluster = true

  capacity_providers = ["EC2"]

  autoscaling_capacity_providers = {
    proxy = {
      auto_scaling_group_arn = module.proxy_asg.autoscaling_group_arn
      managed_scaling = {
        maximum_scaling_step_size = 1
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 100
      }
    }
  }
}

module "proxy_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 7.0"

  name                 = "${var.proxy_cluster_name}-asg"
  create_launch_template = true
  launch_template_name = "${var.proxy_cluster_name}-lt"
  instance_type        = var.proxy_instance_type
  max_size             = 1
  min_size             = 1
  desired_capacity     = 1
  vpc_zone_identifier  = var.proxy_subnet_ids
}

module "proxy_task" {
  source  = "terraform-aws-modules/ecs/aws//modules/task-definition"
  version = "~> 5.0"

  family                   = "proxy"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  container_definitions    = jsonencode([
    {
      name      = "traefik"
      image     = "traefik:v2.9"
      essential = true
      portMappings = [{
        containerPort = 80
        hostPort      = 80
      }]
    }
  ])
}

module "proxy_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name            = "proxy"
  cluster_arn     = module.proxy_cluster.cluster_arn
  task_definition = module.proxy_task.task_definition
  desired_count   = 1
  launch_type     = "EC2"
}

# Web ECS cluster using Fargate
module "web_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"

  cluster_name = var.web_cluster_name
  capacity_providers = ["FARGATE"]
}

module "web_task" {
  source  = "terraform-aws-modules/ecs/aws//modules/task-definition"
  version = "~> 5.0"

  family                   = "web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "site"
      image     = "nginx:latest"
      essential = true
      portMappings = [{
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      }]
    },
    {
      name      = "migrator"
      image     = "alpine:latest"
      command   = ["/bin/true"]
      essential = false
    }
  ])
}

module "web_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name            = "web"
  cluster_arn     = module.web_cluster.cluster_arn
  task_definition = module.web_task.task_definition
  desired_count   = 1
  launch_type     = "FARGATE"
  subnet_ids      = var.web_subnet_ids
  assign_public_ip = true
}

# S3 buckets for each site
module "site_buckets" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  for_each = { for site in var.sites : site.name => site }

  bucket = each.value.bucket_name
}

# Lambda functions per site
module "site_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 6.0"

  for_each = { for site in var.sites : site.name => site }

  function_name = each.value.name
  handler       = each.value.lambda_handler
  runtime       = each.value.lambda_runtime
  source_path   = "lambda/${each.value.name}"

  environment_variables = {
    DB_SECRET_ARN = each.value.secret_arn
  }

  attach_policy_statements = true
  policy_statements = [
    {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [each.value.secret_arn]
    }
  ]
}
