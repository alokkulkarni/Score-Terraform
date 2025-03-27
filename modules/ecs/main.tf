# ECS Module

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-cluster"
    }
  )
}

# ECS Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.name_prefix}-ecs-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name_prefix}-ecs-task-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
  
  tags = var.tags
}

# Create task definitions and services for each service
locals {
  service_map = { for svc in var.services : svc.name => svc }
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "services" {
  for_each = local.service_map
  
  family                   = "${var.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  
  container_definitions = jsonencode([{
    name         = each.key
    image        = each.value.image
    cpu          = each.value.cpu
    memory       = each.value.memory
    essential    = true
    
    portMappings = [{
      containerPort = each.value.container_port
      hostPort      = each.value.container_port
      protocol      = "tcp"
    }]
    
    environment = [
      for key, value in each.value.environment_variables : {
        name  = key
        value = replace(
                  replace(
                    tostring(value), 
                    "\\$\\{resource\\.([^.]+)\\.endpoint\\}", 
                    lookup(var.database_endpoints, "$1", "")
                  ),
                  "\\$\\{resource\\.([^.]+)\\.secrets\\.([^}]+)\\}", 
                  try(
                    tostring(lookup(
                      lookup(var.database_credentials, "$1", {}), 
                      "$2"
                    )),
                    ""
                  )
                )
      }
    ]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.name_prefix}-${each.key}"
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "ecs"
      }
    }
    
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.container_port}${each.value.health_check_path} || exit 1"]
      interval    = each.value.health_check_interval
      timeout     = 5
      retries     = 3
      startPeriod = each.value.health_check_initial_delay
    }
  }])
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${each.key}-task"
    }
  )
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "services" {
  for_each = local.service_map
  
  name              = "/ecs/${var.name_prefix}-${each.key}"
  retention_in_days = 30
  
  tags = var.tags
}

# Target Groups for Public Routes
resource "aws_lb_target_group" "public" {
  for_each = {
    for pair in flatten([
      for svc_name, svc in local.service_map : [
        for route in svc.public_routes : {
          name  = "${svc_name}-${replace(route.path, "/", "-")}-public"
          svc   = svc
          route = route
        }
      ]
    ]) : pair.name => pair
  }
  
  name        = substr("${var.name_prefix}-${each.key}", 0, 32)
  port        = each.value.route.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  
  health_check {
    path                = each.value.svc.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }
  
  tags = var.tags
}

# Target Groups for Internal Routes
resource "aws_lb_target_group" "internal" {
  for_each = {
    for pair in flatten([
      for svc_name, svc in local.service_map : [
        for route in svc.internal_routes : {
          name  = "${svc_name}-${replace(route.path, "/", "-")}-internal"
          svc   = svc
          route = route
        }
      ]
    ]) : pair.name => pair
  }
  
  name        = substr("${var.name_prefix}-${each.key}", 0, 32)
  port        = each.value.route.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  
  health_check {
    path                = each.value.svc.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }
  
  tags = var.tags
}

# Listener Rules for Public Routes
resource "aws_lb_listener_rule" "public" {
  for_each = {
    for pair in flatten([
      for svc_name, svc in local.service_map : [
        for idx, route in svc.public_routes : {
          # Create a stable key that doesn't depend on apply-time attributes
          name        = "${svc_name}-route-${idx}"
          svc         = svc
          route       = route
          priority    = 100 + idx
        }
        # Filter out routes with null listener_arn directly in the for_each
        if lookup(route, "listener_arn", null) != null
      ]
    ]) : pair.name => pair
  }
  
  listener_arn = each.value.route.listener_arn
  priority     = each.value.priority
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public["${each.value.svc.name}-${replace(each.value.route.path, "/", "-")}-public"].arn
  }
  
  condition {
    host_header {
      values = [each.value.route.host]
    }
  }
  
  condition {
    path_pattern {
      values = [each.value.route.path == "/" ? "/*" : "${each.value.route.path}/*"]
    }
  }
}

# Listener Rules for Internal Routes
resource "aws_lb_listener_rule" "internal" {
  for_each = {
    for pair in flatten([
      for svc_name, svc in local.service_map : [
        for idx, route in svc.internal_routes : {
          # Create a stable key that doesn't depend on apply-time attributes
          name        = "${svc_name}-internal-route-${idx}"
          svc         = svc
          route       = route
          priority    = 200 + idx  # Using 200+ to avoid conflicts with public routes
        }
        # Filter out routes with null listener_arn directly in the for_each
        if lookup(route, "listener_arn", null) != null
      ]
    ]) : pair.name => pair
  }
  
  listener_arn = each.value.route.listener_arn
  priority     = each.value.priority
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal["${each.value.svc.name}-${replace(each.value.route.path, "/", "-")}-internal"].arn
  }
  
  condition {
    host_header {
      values = [each.value.route.host]
    }
  }
  
  condition {
    path_pattern {
      values = [each.value.route.path == "/" ? "/*" : "${each.value.route.path}/*"]
    }
  }
}

# ECS Services
resource "aws_ecs_service" "services" {
  for_each = local.service_map
  
  name            = "${var.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  launch_type     = "FARGATE"
  
  desired_count                      = each.value.desired_count
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }
  
  # Create a local stable list of load balancer configurations instead of using dynamic blocks
  dynamic "load_balancer" {
    for_each = concat(
      # Create a list of public load balancer configs with stable keys
      [
        for route in each.value.public_routes : {
          target_group_arn = aws_lb_target_group.public["${each.key}-${replace(route.path, "/", "-")}-public"].arn
          container_name   = each.key
          container_port   = route.port
        }
      ],
      # Add internal load balancer configs with stable keys
      [
        for route in each.value.internal_routes : {
          target_group_arn = aws_lb_target_group.internal["${each.key}-${replace(route.path, "/", "-")}-internal"].arn
          container_name   = each.key
          container_port   = route.port
        }
      ]
    )
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }
  
  # Ignore changes to desired count to allow autoscaling
  lifecycle {
    ignore_changes = [desired_count]
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${each.key}-service"
    }
  )
}

# Get current region
data "aws_region" "current" {}