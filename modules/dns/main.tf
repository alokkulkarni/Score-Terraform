# DNS Module

# Alias records for public load balancer
resource "aws_route53_record" "public" {
  for_each = { for record in var.public_records : record.name => record }
  
  zone_id = var.hosted_zone_id
  name    = "${each.value.name}.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = var.public_lb_dns_name
    zone_id                = var.public_lb_zone_id
    evaluate_target_health = true
  }
}

# Alias records for internal load balancer
resource "aws_route53_record" "internal" {
  for_each = { for record in var.internal_records : record.name => record }
  
  zone_id = var.hosted_zone_id
  name    = "${each.value.name}.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = var.internal_lb_dns_name
    zone_id                = var.internal_lb_zone_id
    evaluate_target_health = true
  }
}

# Health Checks
resource "aws_route53_health_check" "endpoint" {
  for_each = { for check in var.health_checks : check.name => check }
  
  fqdn              = "${each.value.name}.${var.domain_name}"
  port              = 443
  type              = "HTTPS"
  resource_path     = each.value.resource_path
  failure_threshold = each.value.failure_threshold
  request_interval  = each.value.request_interval
  
  tags = merge(
    var.tags,
    {
      Name = "${each.value.name}-health-check"
    }
  )
}
