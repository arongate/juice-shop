output "app_url_https" {
  description = "URL HTTPS (certificat ACM public)"
  value       = "https://${local.fqdn}"
}

output "app_url_http" {
  description = "URL HTTP"
  value       = "http://${local.fqdn}"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.app.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "public_subnet_cidrs" {
  value = local.public_subnet_cidrs
}

output "private_subnet_cidrs" {
  value = local.private_subnet_cidrs
}
