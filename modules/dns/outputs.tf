# Outputs for DNS module

output "public_dns_records" {
  description = "Map of public DNS records"
  value       = { for k, v in aws_route53_record.public : k => v.fqdn }
}

output "internal_dns_records" {
  description = "Map of internal DNS records"
  value       = { for k, v in aws_route53_record.internal : k => v.fqdn }
}

output "health_check_ids" {
  description = "Map of health check IDs"
  value       = { for k, v in aws_route53_health_check.endpoint : k => v.id }
}
