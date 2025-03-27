# Load Balancer Module

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

# ACM Certificate for Public Load Balancer
resource "aws_acm_certificate" "public" {
  count             = var.public_lb_enabled ? 1 : 0
  domain_name       = var.public_domain_name
  validation_method = "DNS"
  
  subject_alternative_names = var.public_subject_alternative_names
  
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-public-cert"
    }
  )

  provider = aws.eu-west-2
}

# ACM Certificate for Internal Load Balancer
resource "aws_acm_certificate" "internal" {
  count             = var.internal_lb_enabled ? 1 : 0
  domain_name       = var.internal_domain_name
  validation_method = "DNS"
  
  subject_alternative_names = var.internal_subject_alternative_names
  
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-internal-cert"
    }
  )

  provider = aws.eu-west-2
}

# DNS validation records for the certificates
resource "aws_route53_record" "public_cert_validation" {
  for_each = var.public_lb_enabled ? {
    for dvo in aws_acm_certificate.public[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_route53_record" "internal_cert_validation" {
  for_each = var.internal_lb_enabled ? {
    for dvo in aws_acm_certificate.internal[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Certificate validation completion
resource "aws_acm_certificate_validation" "public" {
  count                   = var.public_lb_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.public[0].arn
  validation_record_fqdns = [for record in aws_route53_record.public_cert_validation : record.fqdn]
  
  provider = aws.eu-west-2
}

resource "aws_acm_certificate_validation" "internal" {
  count                   = var.internal_lb_enabled ? 1 : 0
  certificate_arn         = aws_acm_certificate.internal[0].arn
  validation_record_fqdns = [for record in aws_route53_record.internal_cert_validation : record.fqdn]
  
  provider = aws.eu-west-2
}

# Public Application Load Balancer
resource "aws_lb" "public" {
  count              = var.public_lb_enabled ? 1 : 0
  name               = "${var.name_prefix}-public-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.public_lb_sg_id]
  subnets            = var.public_subnet_ids
  
  enable_deletion_protection = false
  
  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = "${var.name_prefix}-public-lb-logs"
    enabled = var.access_logs_bucket != ""
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-public-lb"
    }
  )
}

# Public HTTP Listener (redirects to HTTPS)
resource "aws_lb_listener" "public_http" {
  count             = var.public_lb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.public[0].arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Public HTTPS Listener
resource "aws_lb_listener" "public_https" {
  count             = var.public_lb_enabled && var.public_lb_cert_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.public[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.public[0].certificate_arn
  
  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "No routes configured"
      status_code  = "404"
    }
  }
}

# Internal Application Load Balancer
resource "aws_lb" "internal" {
  count              = var.internal_lb_enabled ? 1 : 0
  name               = "${var.name_prefix}-internal-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.internal_lb_sg_id]
  subnets            = var.private_subnet_ids
  
  enable_deletion_protection = false
  
  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = "${var.name_prefix}-internal-lb-logs"
    enabled = var.access_logs_bucket != ""
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-internal-lb"
    }
  )
}

# Internal HTTP Listener (redirects to HTTPS)
resource "aws_lb_listener" "internal_http" {
  count             = var.internal_lb_enabled ? 1 : 0
  load_balancer_arn = aws_lb.internal[0].arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Internal HTTPS Listener
resource "aws_lb_listener" "internal_https" {
  count             = var.internal_lb_enabled && var.internal_lb_cert_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.internal[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.internal[0].certificate_arn
  
  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "No routes configured"
      status_code  = "404"
    }
  }
}
