# Variables for Load Balancer module

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

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

variable "public_lb_sg_id" {
  description = "ID of the security group for the public load balancer"
  type        = string
}

variable "internal_lb_sg_id" {
  description = "ID of the security group for the internal load balancer"
  type        = string
}

variable "access_logs_bucket" {
  description = "S3 bucket name for load balancer access logs"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "public_domain_name" {
  description = "The primary domain name for the public load balancer certificate"
  type        = string
  default     = ""
}

variable "public_subject_alternative_names" {
  description = "A list of subject alternative names for the public load balancer certificate"
  type        = list(string)
  default     = []
}

variable "internal_domain_name" {
  description = "The primary domain name for the internal load balancer certificate"
  type        = string
  default     = ""
}

variable "internal_subject_alternative_names" {
  description = "A list of subject alternative names for the internal load balancer certificate"
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "The Route53 hosted zone ID for DNS validation records"
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "The SSL policy to use for HTTPS listeners"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}
