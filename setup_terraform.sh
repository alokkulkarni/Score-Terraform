#!/bin/bash
set -e

# Create necessary directories
mkdir -p modules/{vpc,security,database,load_balancer,ecs,dns}

# Create module files
echo "Creating Terraform module files..."

# VPC
cp -r ../modules/vpc/* modules/vpc/

# Security
cp -r ../modules/security/* modules/security/

# Database
cp -r ../modules/database/* modules/database/

# Load Balancer
cp -r ../modules/load_balancer/* modules/load_balancer/

# ECS
cp -r ../modules/ecs/* modules/ecs/

# DNS
cp -r ../modules/dns/* modules/dns/

# Copy main Terraform files
cp ../main.tf .
cp ../variables.tf .
cp ../outputs.tf .

echo "Terraform configuration setup complete"
