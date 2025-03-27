# Main Terraform configuration file

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # You might want to uncomment this and configure backend for state management
  # backend "s3" {
  #   bucket         = "terraform-state-bucket"
  #   key            = "score-app/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = var.tags
  }
}

locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_count  = var.public_subnet_count
  private_subnet_count = var.private_subnet_count
  
  tags = var.tags
}

# Security Groups
module "security_groups" {
  source = "./modules/security"
  
  name_prefix     = local.name_prefix
  vpc_id          = module.vpc.vpc_id
  vpc_cidr_block =  module.vpc.vpc_cidr
  tags = var.tags
}

# Database module
module "database" {
  source = "./modules/database"
  
  for_each = { for idx, db in var.databases : db.name => db }
  
  name_prefix               = local.name_prefix
  identifier                = "${local.name_prefix}-${each.key}"
  engine                    = each.value.engine
  engine_version            = each.value.version
  instance_class            = each.value.instance_class
  allocated_storage         = each.value.allocated_storage
  backup_retention_period   = each.value.backup_retention_period
  username                  = each.value.username
  password                  = each.value.password
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_subnet_ids
  db_security_group_id      = module.security_groups.database_security_group_id

  tags = var.tags
}

# Load Balancers
module "load_balancers" {
  source = "./modules/load_balancer"
  
  name_prefix            = local.name_prefix
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = module.vpc.public_subnet_ids
  private_subnet_ids     = module.vpc.private_subnet_ids
  
  public_lb_enabled     = var.public_lb_enabled
  public_lb_cert_arn    = var.public_lb_cert_arn
  internal_lb_enabled   = var.internal_lb_enabled
  internal_lb_cert_arn  = var.internal_lb_cert_arn
  
  public_lb_sg_id       = module.security_groups.public_lb_security_group_id
  internal_lb_sg_id     = module.security_groups.internal_lb_security_group_id
  public_domain_name    = var.domain_name
  hosted_zone_id        = var.hosted_zone_id
  public_subject_alternative_names = ["www.${var.domain_name}"]
  internal_domain_name = "${var.app_name}-internal.${var.domain_name}"
  internal_subject_alternative_names = ["www.${var.app_name}-internal.${var.domain_name}"]
  tags = var.tags
}

# ECS Cluster and Services
module "ecs" {
  source = "./modules/ecs"
  
  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.security_groups.ecs_security_group_id
  
  services = [
    for svc in var.services : {
      name                      = svc.name
      image                     = svc.image
      cpu                       = svc.cpu
      memory                    = svc.memory
      container_port            = svc.container_port
      protocol                  = svc.protocol
      desired_count             = svc.desired_count
      health_check_path         = svc.health_check_path
      health_check_initial_delay = svc.health_check_initial_delay
      health_check_interval     = svc.health_check_interval
      environment_variables     = svc.environment_variables
      
      # Add load balancer target groups if needed
      public_routes = [
        for route in svc.public_routes : {
          host     = route.host
          path     = route.path
          port     = route.port
          lb_arn   = var.public_lb_enabled ? module.load_balancers.public_lb_arn : null
          listener_arn = var.public_lb_enabled ? module.load_balancers.public_https_listener_arn : null
        }
      ]
      
      internal_routes = [
        for route in svc.internal_routes : {
          host     = route.host
          path     = route.path
          port     = route.port
          lb_arn   = var.internal_lb_enabled ? module.load_balancers.internal_lb_arn : null
          listener_arn = var.internal_lb_enabled ? module.load_balancers.internal_https_listener_arn : null
        }
      ]
      
      # Add database dependencies
      depends_on = [
        for dep in svc.depends_on : contains(keys(module.database), dep) ? module.database[dep].db_instance_id : ""
      ]
    }
  ]
  
  # Pass database endpoints to services that need them
  database_endpoints = {
    for db_name, db in module.database : db_name => db.db_endpoint
  }
  
  database_credentials = {
    for db_name, db in module.database : db_name => {
      username = db.db_username
      password = db.db_password
    }
  }
  
  tags = var.tags
}

# Route53 DNS Records
module "dns" {
  source = "./modules/dns"
  count  = var.domain_name != "" ? 1 : 0
  
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
  
  public_lb_dns_name    = var.public_lb_enabled ? module.load_balancers.public_lb_dns_name : ""
  public_lb_zone_id     = var.public_lb_enabled ? module.load_balancers.public_lb_zone_id : ""
  internal_lb_dns_name  = var.internal_lb_enabled ? module.load_balancers.internal_lb_dns_name : ""
  internal_lb_zone_id   = var.internal_lb_enabled ? module.load_balancers.internal_lb_zone_id : ""
  
  # Collect all hostnames from services
  public_records = flatten([
    for svc in var.services : [
      for route in svc.public_routes : {
        name = replace(route.host, ".${var.domain_name}", "")
      }
    ]
  ])
  
  internal_records = flatten([
    for svc in var.services : [
      for route in svc.internal_routes : {
        name = replace(route.host, ".${var.domain_name}", "")
      }
    ]
  ])
  
  tags = var.tags
}
