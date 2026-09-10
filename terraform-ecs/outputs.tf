output "alb_dns_name" {
  description = "Public URL of the load balancer — the app will be reachable here"
  value       = "http://${aws_lb.main.dns_name}/${var.project_name}/api/ping"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.main.name
}

output "rds_endpoint" {
  description = "RDS endpoint (private — not reachable from outside the VPC)"
  value       = aws_db_instance.main.address
  sensitive   = true
}
