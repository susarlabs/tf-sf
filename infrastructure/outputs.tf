output "proxy_cluster_arn" {
  description = "ARN of the proxy ECS cluster"
  value       = aws_ecs_cluster.proxy_cluster.arn
}

output "web_cluster_arn" {
  description = "ARN of the web ECS cluster"
  value       = aws_ecs_cluster.web_cluster.arn
}

output "proxy_cluster_name" {
  description = "Name of the proxy ECS cluster"
  value       = aws_ecs_cluster.proxy_cluster.name
}

output "web_cluster_name" {
  description = "Name of the web ECS cluster"
  value       = aws_ecs_cluster.web_cluster.name
}

output "site_s3_buckets" {
  description = "S3 buckets created for each site"
  value = {
    for site_name, bucket in aws_s3_bucket.site_buckets : site_name => {
      bucket_name = bucket.bucket
      bucket_arn  = bucket.arn
    }
  }
}

output "site_lambda_functions" {
  description = "Lambda functions created for each site"
  value = {
    for site_name, lambda_func in aws_lambda_function.site_lambdas : site_name => {
      function_name = lambda_func.function_name
      function_arn  = lambda_func.arn
    }
  }
}

output "proxy_security_group_id" {
  description = "Security group ID for the proxy cluster"
  value       = aws_security_group.proxy_sg.id
}

output "web_security_group_id" {
  description = "Security group ID for the web cluster"
  value       = aws_security_group.web_sg.id
}