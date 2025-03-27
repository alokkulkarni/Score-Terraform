# Database Module

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Subnet group for ${var.name_prefix} database"
  subnet_ids  = var.subnet_ids
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-db-subnet-group"
    }
  )
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  name        = "${var.name_prefix}-db-pg"
  family      = "${var.engine}${substr(var.engine_version, 0, 2)}"
  description = "Parameter group for ${var.name_prefix} database"
  
  parameter {
    name  = "log_connections"
    value = "1"
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-db-pg"
    }
  )
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier             = var.identifier
  engine                 = var.engine
  engine_version         = var.engine_version
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  storage_type           = "gp2"
  
  db_name                = replace(var.name_prefix, "-", "")
  username               = var.username
  password               = var.password
  
  vpc_security_group_ids = [var.db_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  
  multi_az               = var.environment == "prod"
  skip_final_snapshot    = var.environment != "prod"
  deletion_protection    = var.environment == "prod"
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-db"
    }
  )
  
  lifecycle {
    ignore_changes = [password]
  }
}
