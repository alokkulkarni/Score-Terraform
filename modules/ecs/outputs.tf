# Outputs for ECS module

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "task_definitions" {
  description = "ARNs of the ECS task definitions"
  value       = { for name, task in aws_ecs_task_definition.services : name => task.arn }
}

output "service_names" {
  description = "Names of the ECS services"
  value       = { for name, svc in aws_ecs_service.services : name => svc.name }
}

output "service_arns" {
  description = "ARNs of the ECS services"
  value       = { for name, svc in aws_ecs_service.services : name => svc.id }
}

output "public_target_groups" {
  description = "ARNs of the public target groups"
  value       = { for name, tg in aws_lb_target_group.public : name => tg.arn }
}

output "internal_target_groups" {
  description = "ARNs of the internal target groups"
  value       = { for name, tg in aws_lb_target_group.internal : name => tg.arn }
}
