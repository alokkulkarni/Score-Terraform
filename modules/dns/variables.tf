# Variables for DNS module

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "public_lb_dns_name" {
  description = "DNS name of the public load balancer"
  type        = string
  default     = ""
}

variable "public_lb_zone_id" {
  description = "Zone ID of the public load balancer"
  type        = string
  default     = ""
}

variable "internal_lb_dns_name" {
  description = "DNS name of the internal load balancer"
  type        = string
  default     = ""
}

variable "internal_lb_zone_id" {
  description = "Zone ID of the internal load balancer"
  type        = string
  default     = ""
}

variable "public_records" {
  description = "List of public DNS records to create"
  type        = list(object({
    name = string
  }))
  default     = []
}

variable "internal_records" {
  description = "List of internal DNS records to create"
  type        = list(object({
    name = string
  }))
  default     = []
}

variable "health_checks" {
  description = "List of health checks to create"
  type        = list(object({
    name              = string
    resource_path     = string
    failure_threshold = number
    request_interval  = number
  }))
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
