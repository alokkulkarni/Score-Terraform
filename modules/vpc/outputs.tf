# Outputs for VPC module

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = var.private_subnet_count > 0 ? aws_nat_gateway.main[0].id : null
}

output "public_route_table_id" {
  description = "ID of the route table for public subnets"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the route table for private subnets"
  value       = aws_route_table.private.id
}
