# Variables for ECS module

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets where ECS tasks will run"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ID of the security group for ECS tasks"
  type        = string
}

variable "services" {
  description = "List of services to deploy"
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
      host        = string
      path        = string
      port        = number
      lb_arn      = string
      listener_arn = string
    }))
    
    internal_routes = list(object({
      host        = string
      path        = string
      port        = number
      lb_arn      = string
      listener_arn = string
    }))
    
    depends_on = list(string)
  }))
  default = []
}

variable "database_endpoints" {
  description = "Map of database names to endpoints"
  type        = map(string)
  default     = {}
}

variable "database_credentials" {
  description = "Map of database names to credential objects"
  type        = map(object({
    username = string
    password = string
  }))
  default     = {}
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
