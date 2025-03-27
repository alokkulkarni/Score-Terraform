# Outputs from the Terraform deployment

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_lb_dns_name" {
  description = "DNS name of the public load balancer"
  value       = var.public_lb_enabled ? module.load_balancers.public_lb_dns_name : null
}

output "internal_lb_dns_name" {
  description = "DNS name of the internal load balancer"
  value       = var.internal_lb_enabled ? module.load_balancers.internal_lb_dns_name : null
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_names" {
  description = "Names of the ECS services"
  value       = module.ecs.service_names
}

output "database_endpoints" {
  description = "Endpoints of the RDS instances"
  value       = { for db_name, db in module.database : db_name => db.db_endpoint }
  sensitive   = true
}

output "public_urls" {
  description = "Public URLs for the services"
  value = flatten([
    for svc in var.services : [
      for route in svc.public_routes : {
        name = svc.name
        url  = "https://${route.host}"
      }
    ]
  ])
}

output "internal_urls" {
  description = "Internal URLs for the services"
  value = flatten([
    for svc in var.services : [
      for route in svc.internal_routes : {
        name = svc.name
        url  = "https://${route.host}"
      }
    ]
  ])
}
