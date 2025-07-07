# Infrastructure

This directory contains Terraform configuration files to provision AWS infrastructure for a multi-site deployment with ECS clusters, S3 buckets, and Lambda functions.

## Architecture

The infrastructure includes:

- **Proxy ECS Cluster (EC2)**: Runs Traefik as a reverse proxy with auto-scaling
- **Web ECS Cluster (Fargate)**: Hosts site applications and one-time migrator tasks
- **S3 Buckets**: One bucket per site for file storage
- **Lambda Functions**: One function per site for database connections and Secrets Manager access

## Files

- `main.tf`: Main infrastructure configuration
- `variables.tf`: Variable declarations
- `outputs.tf`: Output definitions
- `user_data.sh`: EC2 user data script for ECS cluster registration

## Usage

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Set required variables in a `.tfvars` file or via environment variables:
   ```bash
   vpc_id = "vpc-xxxxxxxxx"
   public_subnet_ids = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
   private_subnet_ids = ["subnet-zzzzzzzzz", "subnet-aaaaaaaaa"]
   ```

3. Plan the deployment:
   ```bash
   terraform plan -var-file="terraform.tfvars"
   ```

4. Apply the configuration:
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```

## Required Variables

- `vpc_id`: VPC ID where resources will be created
- `public_subnet_ids`: List of public subnet IDs for the proxy cluster
- `private_subnet_ids`: List of private subnet IDs for the web cluster

## Optional Variables

- `aws_region`: AWS region (default: us-west-2)
- `proxy_cluster_name`: Name of the proxy ECS cluster
- `web_cluster_name`: Name of the web ECS cluster
- `proxy_instance_type`: EC2 instance type for proxy cluster
- `sites`: List of site configurations (name, domain, environment)
- `environment`: Environment name (default: production)

## Outputs

- ECS cluster ARNs
- S3 bucket details
- Lambda function details
- Security group IDs