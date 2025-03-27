# Outputs for Security Groups module

output "public_lb_security_group_id" {
  description = "ID of the security group for the public load balancer"
  value       = aws_security_group.public_lb.id
}

output "internal_lb_security_group_id" {
  description = "ID of the security group for the internal load balancer"
  value       = aws_security_group.internal_lb.id
}

output "ecs_security_group_id" {
  description = "ID of the security group for ECS services"
  value       = aws_security_group.ecs.id
}

output "database_security_group_id" {
  description = "ID of the security group for database instances"
  value       = aws_security_group.database.id
}
