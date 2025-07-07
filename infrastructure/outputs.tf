output "proxy_cluster_arn" {
  value = module.proxy_cluster.cluster_arn
}

output "web_cluster_arn" {
  value = module.web_cluster.cluster_arn
}
