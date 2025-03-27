# Outputs for Load Balancer module

output "public_lb_arn" {
  description = "ARN of the public load balancer"
  value       = var.public_lb_enabled ? aws_lb.public[0].arn : null
}

output "public_lb_dns_name" {
  description = "DNS name of the public load balancer"
  value       = var.public_lb_enabled ? aws_lb.public[0].dns_name : null
}

output "public_lb_zone_id" {
  description = "Zone ID of the public load balancer"
  value       = var.public_lb_enabled ? aws_lb.public[0].zone_id : null
}

output "public_http_listener_arn" {
  description = "ARN of the public HTTP listener"
  value       = var.public_lb_enabled ? aws_lb_listener.public_http[0].arn : null
}

output "public_https_listener_arn" {
  description = "ARN of the public HTTPS listener"
  value       = var.public_lb_enabled && var.public_lb_cert_arn != "" ? aws_lb_listener.public_https[0].arn : null
}

output "internal_lb_arn" {
  description = "ARN of the internal load balancer"
  value       = var.internal_lb_enabled ? aws_lb.internal[0].arn : null
}

output "internal_lb_dns_name" {
  description = "DNS name of the internal load balancer"
  value       = var.internal_lb_enabled ? aws_lb.internal[0].dns_name : null
}

output "internal_lb_zone_id" {
  description = "Zone ID of the internal load balancer"
  value       = var.internal_lb_enabled ? aws_lb.internal[0].zone_id : null
}

output "internal_http_listener_arn" {
  description = "ARN of the internal HTTP listener"
  value       = var.internal_lb_enabled ? aws_lb_listener.internal_http[0].arn : null
}

output "internal_https_listener_arn" {
  description = "ARN of the internal HTTPS listener"
  value       = var.internal_lb_enabled && var.internal_lb_cert_arn != "" ? aws_lb_listener.internal_https[0].arn : null
}
