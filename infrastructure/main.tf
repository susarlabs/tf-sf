terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# IAM role for ECS tasks
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM role for ECS instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.environment}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.environment}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# Security Groups
resource "aws_security_group" "proxy_sg" {
  name        = "${var.environment}-proxy-sg"
  description = "Security group for proxy ECS cluster"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-proxy-sg"
  }
}

resource "aws_security_group" "web_sg" {
  name        = "${var.environment}-web-sg"
  description = "Security group for web ECS cluster"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_sg.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-web-sg"
  }
}

# Launch Template for Proxy Cluster
resource "aws_launch_template" "proxy_lt" {
  name_prefix   = "${var.environment}-proxy-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.proxy_instance_type

  vpc_security_group_ids = [aws_security_group.proxy_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name = aws_ecs_cluster.proxy_cluster.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.environment}-proxy-instance"
    }
  }
}

# Auto Scaling Group for Proxy Cluster
resource "aws_autoscaling_group" "proxy_asg" {
  name                = "${var.environment}-proxy-asg"
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = []
  health_check_type   = "EC2"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.proxy_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-proxy-asg"
    propagate_at_launch = false
  }
}

# ECS Clusters
resource "aws_ecs_cluster" "proxy_cluster" {
  name = var.proxy_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.proxy_cluster_name
  }
}

resource "aws_ecs_cluster" "web_cluster" {
  name = var.web_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.web_cluster_name
  }
}

# ECS Capacity Provider for Proxy Cluster
resource "aws_ecs_capacity_provider" "proxy_cp" {
  name = "${var.environment}-proxy-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.proxy_asg.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "proxy_cluster_cp" {
  cluster_name       = aws_ecs_cluster.proxy_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.proxy_cp.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.proxy_cp.name
  }
}

# Traefik Task Definition for Proxy Cluster
resource "aws_ecs_task_definition" "traefik" {
  family                   = "${var.environment}-traefik"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "traefik"
      image     = "traefik:v2.10"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        },
        {
          containerPort = 443
          hostPort      = 443
          protocol      = "tcp"
        },
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      command = [
        "--api.dashboard=true",
        "--api.insecure=true",
        "--providers.ecs=true",
        "--providers.ecs.clusters=${aws_ecs_cluster.web_cluster.name}",
        "--providers.ecs.region=${var.aws_region}",
        "--entrypoints.web.address=:80",
        "--entrypoints.websecure.address=:443"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-traefik"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log Group for Traefik
resource "aws_cloudwatch_log_group" "traefik" {
  name              = "/ecs/${var.environment}-traefik"
  retention_in_days = 7
}

# Traefik Service
resource "aws_ecs_service" "traefik" {
  name            = "${var.environment}-traefik"
  cluster         = aws_ecs_cluster.proxy_cluster.id
  task_definition = aws_ecs_task_definition.traefik.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.proxy_cp.name
    weight            = 100
  }

  depends_on = [aws_ecs_cluster_capacity_providers.proxy_cluster_cp]
}

# S3 Buckets for each site
resource "aws_s3_bucket" "site_buckets" {
  for_each = { for site in var.sites : site.name => site }
  bucket   = "${var.environment}-${each.value.name}-bucket"

  tags = {
    Name        = "${var.environment}-${each.value.name}-bucket"
    Site        = each.value.name
    Environment = each.value.environment
  }
}

resource "aws_s3_bucket_versioning" "site_bucket_versioning" {
  for_each = aws_s3_bucket.site_buckets
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site_bucket_encryption" {
  for_each = aws_s3_bucket.site_buckets
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  for_each = { for site in var.sites : site.name => site }
  name     = "${var.environment}-${each.value.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  for_each = aws_iam_role.lambda_role
  name     = "${var.environment}-${each.key}-lambda-policy"
  role     = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.site_buckets[each.key].arn}/*"
      }
    ]
  })
}

# Lambda functions for each site
resource "aws_lambda_function" "site_lambdas" {
  for_each      = { for site in var.sites : site.name => site }
  filename      = "lambda_function.zip"
  function_name = "${var.environment}-${each.value.name}-function"
  role          = aws_iam_role.lambda_role[each.key].arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 30

  environment {
    variables = {
      SITE_NAME   = each.value.name
      SITE_DOMAIN = each.value.domain
      DB_HOST     = var.db_host
      DB_NAME     = var.db_name
      S3_BUCKET   = aws_s3_bucket.site_buckets[each.key].bucket
    }
  }

  tags = {
    Name        = "${var.environment}-${each.value.name}-function"
    Site        = each.value.name
    Environment = each.value.environment
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each          = { for site in var.sites : site.name => site }
  name              = "/aws/lambda/${var.environment}-${each.value.name}-function"
  retention_in_days = 7
}

# Create a dummy Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content  = <<EOF
import json
import boto3
import os

def handler(event, context):
    # Lambda function for site: {SITE_NAME}
    # This function handles DB connections and Secrets Manager access
    
    site_name = os.environ.get('SITE_NAME')
    site_domain = os.environ.get('SITE_DOMAIN')
    db_host = os.environ.get('DB_HOST')
    db_name = os.environ.get('DB_NAME')
    s3_bucket = os.environ.get('S3_BUCKET')
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Lambda function for {site_name} executed successfully',
            'site_domain': site_domain,
            'db_host': db_host,
            'db_name': db_name,
            's3_bucket': s3_bucket
        })
    }
EOF
    filename = "index.py"
  }
}