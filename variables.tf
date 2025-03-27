# Variables for the Terraform configuration

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_count" {
  description = "Number of public subnets to create"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets to create"
  type        = number
  default     = 2
}

# Load Balancer Configuration
variable "public_lb_enabled" {
  description = "Whether to create a public load balancer"
  type        = bool
  default     = true
}

variable "public_lb_cert_arn" {
  description = "ARN of the TLS certificate for the public load balancer"
  type        = string
  default     = ""
}

variable "internal_lb_enabled" {
  description = "Whether to create an internal load balancer"
  type        = bool
  default     = false
}

variable "internal_lb_cert_arn" {
  description = "ARN of the TLS certificate for the internal load balancer"
  type        = string
  default     = ""
}

# DNS Configuration
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
  default     = ""
}

# Database Configuration
variable "databases" {
  description = "List of database configurations"
  type = list(object({
    name                    = string
    engine                  = string
    version                 = string
    instance_class          = string
    allocated_storage       = number
    backup_retention_period = number
    username                = string
    password                = string
  }))
  default = []
}

# Services Configuration
variable "services" {
  description = "List of container service configurations"
  type = list(object({
    name                       = string
    image                      = string
    cpu                        = number
    memory                     = number
    container_port             = number
    protocol                   = string
    desired_count              = number
    health_check_path          = string
    health_check_initial_delay = number
    health_check_interval      = number
    environment_variables      = map(string)
    
    public_routes = list(object({
      host = string
      path = string
      port = number
    }))
    
    internal_routes = list(object({
      host = string
      path = string
      port = number
    }))
    
    depends_on = list(string)
  }))
  default = []
}
