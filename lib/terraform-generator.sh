#!/bin/bash
# terraform-generator.sh
#
# Description: Functions for generating Terraform configurations

# Generate Terraform configurations based on SCORE file
generate_terraform_config() {
    log "INFO" "Generating Terraform configurations in $OUTPUT_DIR..."
    
    # Create output directory
    ensure_directory "$OUTPUT_DIR"
    ensure_directory "$OUTPUT_DIR/modules"
    
    # Load component info
    COMPONENT_INFO=$(cat "$COMPONENT_INFO_FILE")
    
    # Copy required modules
    copy_required_modules
    
    # Generate main configuration files
    generate_root_files
    
    # Generate workload module
    generate_workload_module
    
    log "SUCCESS" "Terraform configuration generated in $OUTPUT_DIR"
}

# Generate root Terraform files
generate_root_files() {
    log_verbose "Generating root Terraform files"
    
    # Generate provider.tf
    generate_provider_tf
    
    # Generate variables.tf
    generate_variables_tf
    
    # Generate main.tf
    generate_main_tf
    
    # Generate outputs.tf
    generate_outputs_tf
}

# Generate provider.tf
generate_provider_tf() {
    log_verbose "Generating provider.tf"
    
    local provider=$(echo "$COMPONENT_INFO" | jq -r '.metadata.provider')
    local region=$(echo "$COMPONENT_INFO" | jq -r '.metadata.region')
    
    cat > "$OUTPUT_DIR/provider.tf" << EOF
# Provider configuration
# Generated from SCORE file: $SCORE_FILE

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    $provider = {
      source  = "hashicorp/$provider"
      version = "~> 4.0"
    }
  }
}

provider "$provider" {
  region = var.region
}
EOF
}

# Generate variables.tf
generate_variables_tf() {
    log_verbose "Generating variables.tf"
    
    local project=$(echo "$COMPONENT_INFO" | jq -r '.metadata.name')
    local env=$(echo "$COMPONENT_INFO" | jq -r '.metadata.environment')
    local region=$(echo "$COMPONENT_INFO" | jq -r '.metadata.region')
    
    # Get tags from SCORE file
    local tags_json=$(yq eval -o=json '.metadata.tags // {}' "$SCORE_FILE")
    
    cat > "$OUTPUT_DIR/variables.tf" << EOF
# Variables configuration
# Generated from SCORE file: $SCORE_FILE

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "$project"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "$env"
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "$region"
}

variable "resource_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = $tags_json
}
EOF

    # Add database variables if PostgreSQL is detected
    if $(echo "$COMPONENT_INFO" | jq -r '.hasPostgres'); then
        local db_username=$(get_postgres_credentials "username")
        local db_password=$(get_postgres_credentials "password")
        
        cat >> "$OUTPUT_DIR/variables.tf" << EOF

# Database credentials (PostgreSQL)
variable "db_username" {
  description = "Database username for PostgreSQL"
  type        = string
  default     = "$db_username"
  sensitive   = true
}

variable "db_password" {
  description = "Database password for PostgreSQL"
  type        = string
  default     = "$db_password"
  sensitive   = true
}
EOF
    fi
    
    # Add Spring Boot variables if detected
    if $(echo "$COMPONENT_INFO" | jq -r '.hasSpringBoot'); then
        local spring_image=$(get_spring_boot_image)
        
        cat >> "$OUTPUT_DIR/variables.tf" << EOF

# Spring Boot image URI
variable "spring_image_uri" {
  description = "Spring Boot application image URI"
  type        = string
  default     = "$spring_image"
}
EOF
    fi
}

# Generate main.tf
generate_main_tf() {
    log_verbose "Generating main.tf"
    
    local has_postgres=$(echo "$COMPONENT_INFO" | jq -r '.hasPostgres')
    local has_spring_boot=$(echo "$COMPONENT_INFO" | jq -r '.hasSpringBoot')
    
    cat > "$OUTPUT_DIR/main.tf" << EOF
# Main Terraform configuration
# Generated from SCORE file: $SCORE_FILE

module "workload" {
  source = "./modules/workload"
  
  project_name    = var.project_name
  environment     = var.environment
  region          = var.region
  resource_tags   = var.resource_tags
EOF

    if [ "$has_postgres" == "true" ]; then
        cat >> "$OUTPUT_DIR/main.tf" << EOF
  db_username     = var.db_username
  db_password     = var.db_password
EOF
    fi

    if [ "$has_spring_boot" == "true" ]; then
        cat >> "$OUTPUT_DIR/main.tf" << EOF
  spring_image_uri = var.spring_image_uri
EOF
    fi

    cat >> "$OUTPUT_DIR/main.tf" << EOF
}
EOF
}

# Generate outputs.tf
generate_outputs_tf() {
    log_verbose "Generating outputs.tf"
    
    cat > "$OUTPUT_DIR/outputs.tf" << EOF
# Output values
# Generated from SCORE file: $SCORE_FILE

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.workload.public_subnets
}
EOF

    # Add component-specific outputs
    local components=$(echo "$COMPONENT_INFO" | jq -r '.components[] | "\(.name)|\(.type)"')
    
    while IFS="|" read -r name type; do
        case "$type" in
            "container")
                cat >> "$OUTPUT_DIR/outputs.tf" << EOF

output "${name}_url" {
  description = "URL to access the ${name} service"
  value       = module.workload.${name}_url
}

output "${name}_load_balancer_dns" {
  description = "Load balancer DNS name for ${name}"
  value       = module.workload.${name}_load_balancer_dns
}
EOF
                ;;
            "database")
                cat >> "$OUTPUT_DIR/outputs.tf" << EOF

output "${name}_endpoint" {
  description = "Database endpoint for ${name}"
  value       = module.workload.${name}_endpoint
}

output "${name}_address" {
  description = "Database address for ${name}"
  value       = module.workload.${name}_address
}

output "${name}_port" {
  description = "Database port for ${name}"
  value       = module.workload.${name}_port
}
EOF
                ;;
            "function")
                cat >> "$OUTPUT_DIR/outputs.tf" << EOF

output "${name}_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.workload.${name}_function_arn
}

output "${name}_function_name" {
  description = "Name of the Lambda function"
  value       = module.workload.${name}_function_name
}
EOF
                ;;
        esac
    done <<< "$components"
}

# Generate workload module
generate_workload_module() {
    log_verbose "Generating workload module"
    
    local workload_dir="$OUTPUT_DIR/modules/workload"
    ensure_directory "$workload_dir"
    
    # Generate workload module files
    generate_workload_variables "$workload_dir"
    generate_workload_main "$workload_dir"
    generate_workload_outputs "$workload_dir"
}

# Generate variables.tf for workload module
generate_workload_variables() {
    local workload_dir="$1"
    log_verbose "Generating variables.tf for workload module"
    
    cat > "$workload_dir/variables.tf" << EOF
# Workload module variables
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
}

variable "resource_tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
EOF

    # Add PostgreSQL variables if required
    if $(echo "$COMPONENT_INFO" | jq -r '.hasPostgres'); then
        cat >> "$workload_dir/variables.tf" << EOF

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
EOF
    fi
    
    # Add Spring Boot variables if required
    if $(echo "$COMPONENT_INFO" | jq -r '.hasSpringBoot'); then
        cat >> "$workload_dir/variables.tf" << EOF

variable "spring_image_uri" {
  description = "Spring Boot application image URI"
  type        = string
}
EOF
    fi
}

# Generate main.tf for workload module
generate_workload_main() {
    local workload_dir="$1"
    log_verbose "Generating main.tf for workload module"
    
    local cidr_block=$(yq_extract "$SCORE_FILE" '.resources.networking.cidr' "10.0.0.0/16")
    
    # Start with locals and network module
    cat > "$workload_dir/main.tf" << EOF
# Workload module main configuration
# Generated from SCORE file: $SCORE_FILE

locals {
  name_prefix = "\${var.project_name}-\${var.environment}"
}

# Create VPC and network infrastructure using pre-existing module
# Implements AWS Well-Architected Framework best practices for networking
module "network" {
  source = "../network"
  
  name        = local.name_prefix
  environment = var.environment
  region      = var.region
  cidr_block  = "${cidr_block}"
  
  tags = var.resource_tags
}

# Security and compliance infrastructure based on AWS Well-Architected Framework
module "security" {
  source = "../security"
  
  name        = local.name_prefix
  environment = var.environment
  vpc_id      = module.network.vpc_id
  
  tags = var.resource_tags
}
EOF

    # Process database workloads first (for dependency ordering)
    local db_components=$(get_workloads_by_type "database")
    
    for db_name in $db_components; do
        log_verbose "Processing database workload: $db_name"
        
        # Extract database properties from SCORE file
        local engine=$(extract_workload_property "$db_name" "engine" "postgres")
        local version=$(extract_workload_property "$db_name" "version" "13.4")
        local instance=$(extract_workload_property "$db_name" "resources.instance" "db.t3.micro")
        local storage=$(extract_workload_property "$db_name" "resources.storage" "20")
        local backup_retention=$(extract_workload_property "$db_name" "backup.retention" "7")
        local db_formatted_name=$(echo "$db_name" | sed 's/-/_/g')
        
        # Generate database module
        cat >> "$workload_dir/main.tf" << EOF

# Database workload: ${db_name}
module "${db_name}" {
  source = "../database"
  
  name        = "${db_name}"
  environment = var.environment
  vpc_id      = module.network.vpc_id
  subnets     = module.network.private_subnets
  
  engine      = "${engine}"
  version     = "${version}"
  instance    = "${instance}"
  storage     = ${storage}
  db_name     = "${db_formatted_name}"
  backup_retention = ${backup_retention}
  
  # Database credentials from variables
  username    = var.db_username
  password    = var.db_password
  
  # Security groups from security module
  security_groups = [module.security.database_security_group_id]
  
  tags        = var.resource_tags
}
EOF
    done
    
    # Process container workloads
    local container_components=$(get_workloads_by_type "container")
    
    for container_name in $container_components; do
        log_verbose "Processing container workload: $container_name"
        
        # Extract container properties from SCORE file
        local cpu=$(extract_workload_property "$container_name" "resources.cpu" "256")
        local memory=$(extract_workload_property "$container_name" "resources.memory" "512")
        local port=$(extract_workload_property "$container_name" "ports[0].port" "80")
        local replicas=$(extract_workload_property "$container_name" "replicas" "1")
        local health_check_path=$(extract_workload_property "$container_name" "healthCheck.path" "/")
        
        # Process environment variables
        local env_vars=$(yq eval -o=json ".workloads[\"$container_name\"].environment // {}" "$SCORE_FILE")
        
        # Determine if this is a Spring Boot container
        local is_spring_boot="false"
        local image_entry
        
        if echo "$env_vars" | grep -q "SPRING_"; then
            is_spring_boot="true"
            image_entry="image       = var.spring_image_uri"
        else
            local image=$(extract_workload_property "$container_name" "image" "nginx:latest")
            image_entry="image       = \"$image\""
        fi
        
        # Get dependencies
        local dependencies=""
        local depends_on=$(yq eval -o=json ".workloads[\"$container_name\"].dependsOn // []" "$SCORE_FILE")
        
        # Replace database references in environment variables
        if [ "$depends_on" != "[]" ]; then
            for dep in $(echo "$depends_on" | jq -r '.[]'); do
                if echo "$db_components" | grep -q "$dep"; then
                    # Replace ${resource.db.endpoint} style references
                    env_vars=$(echo "$env_vars" | sed "s|\\\${resource.$dep.endpoint}|\${module.$dep.endpoint}|g")
                    
                    # Replace ${resource.db.secrets.username} style references
                    env_vars=$(echo "$env_vars" | sed "s|\\\${resource.$dep.secrets.username}|\${var.db_username}|g")
                    env_vars=$(echo "$env_vars" | sed "s|\\\${resource.$dep.secrets.password}|\${var.db_password}|g")
                fi
            done
            
            # Create depends_on list for Terraform
            local depends_list=""
            for dep in $(echo "$depends_on" | jq -r '.[]'); do
                if [ -n "$depends_list" ]; then
                    depends_list="$depends_list, "
                fi
                depends_list="${depends_list}module.${dep}"
            done
            
            if [ -n "$depends_list" ]; then
                dependencies="depends_on = [$depends_list]"
            fi
        fi
        
        # Generate container module
        cat >> "$workload_dir/main.tf" << EOF

# Container workload: ${container_name}
module "${container_name}" {
  source = "../container"
  
  name        = "${container_name}"
  environment = var.environment
  vpc_id      = module.network.vpc_id
  subnets     = module.network.private_subnets
  public_subnets = module.network.public_subnets
  
  ${image_entry}
  cpu         = ${cpu}
  memory      = ${memory}
  port        = ${port}
  replicas    = ${replicas}
  health_check_path = "${health_check_path}"
  
  environment_variables = ${env_vars}
  
  # Security groups from security module
  security_groups = [module.security.container_security_group_id]
  
  # Spring Boot flag
  is_spring_boot = ${is_spring_boot}
  
  tags        = var.resource_tags
  
  # Dependencies on other resources
  ${dependencies}
}
EOF
    done
    
    # Process function workloads
    local function_components=$(get_workloads_by_type "function")
    
    for function_name in $function_components; do
        log_verbose "Processing function workload: $function_name"
        
        # Extract function properties from SCORE file
        local runtime=$(extract_workload_property "$function_name" "runtime" "nodejs16.x")
        local handler=$(extract_workload_property "$function_name" "handler" "index.handler")
        local memory=$(extract_workload_property "$function_name" "resources.memory" "128")
        local timeout=$(extract_workload_property "$function_name" "timeout" "30")
        local env_vars=$(yq eval -o=json ".workloads[\"$function_name\"].environment // {}" "$SCORE_FILE")
        
        # Generate function module
        cat >> "$workload_dir/main.tf" << EOF

# Function workload: ${function_name}
module "${function_name}" {
  source = "../function"
  
  name        = "${function_name}"
  environment = var.environment
  vpc_id      = module.network.vpc_id
  subnets     = module.network.private_subnets
  
  runtime     = "${runtime}"
  handler     = "${handler}"
  memory      = ${memory}
  timeout     = ${timeout}
  
  environment_variables = ${env_vars}
  
  # Security groups from security module
  security_groups = [module.security.lambda_security_group_id]
  
  tags        = var.resource_tags
}
EOF
    done
}

# Generate outputs.tf for workload module
generate_workload_outputs() {
    local workload_dir="$1"
    log_verbose "Generating outputs.tf for workload module"
    
    cat > "$workload_dir/outputs.tf" << EOF
# Workload module outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.network.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.network.public_subnets
}
EOF

    # Add component-specific outputs
    local components=$(echo "$COMPONENT_INFO" | jq -r '.components[] | "\(.name)|\(.type)"')
    
    while IFS="|" read -r name type; do
        case "$type" in
            "container")
                cat >> "$workload_dir/outputs.tf" << EOF

output "${name}_url" {
  description = "URL to access the ${name} service"
  value       = module.${name}.load_balancer_url
}

output "${name}_load_balancer_dns" {
  description = "Load balancer DNS name for ${name}"
  value       = module.${name}.load_balancer_dns
}
EOF
                ;;
            "database")
                cat >> "$workload_dir/outputs.tf" << EOF

output "${name}_endpoint" {
  description = "Database endpoint for ${name}"
  value       = module.${name}.endpoint
}

output "${name}_address" {
  description = "Database address for ${name}"
  value       = module.${name}.address
}

output "${name}_port" {
  description = "Database port for ${name}"
  value       = module.${name}.port
}

output "${name}_name" {
  description = "Database name for ${name}"
  value       = module.${name}.name
}
EOF
                ;;
            "function")
                cat >> "$workload_dir/outputs.tf" << EOF

output "${name}_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.${name}.function_arn
}

output "${name}_function_name" {
  description = "Name of the Lambda function"
  value       = module.${name}.function_name
}
EOF
                ;;
        esac
    done <<< "$components"
}

# Generate documentation
generate_documentation() {
    log "INFO" "Generating documentation..."
    
    local project_name=$(echo "$COMPONENT_INFO" | jq -r '.metadata.name')
    local component_list=""
    
    # Build component list
    local components=$(echo "$COMPONENT_INFO" | jq -r '.components[] | "\(.name)|\(.type)"')
    while IFS="|" read -r name type; do
        component_list="${component_list}- **${name}** (${type})\n"
    done <<< "$components"
    
    # Create README.md
    cat > "README.md" << EOF
# SCORE Deployment: ${project_name}

This project contains Terraform configurations generated from the SCORE file: ${SCORE_FILE}

## Components Detected

$(echo -e "${component_list}")

## Deployment Instructions

1. Review the generated Terraform configurations in the \`${OUTPUT_DIR}\` directory.

2. Set any required environment variables:
$([ "$(echo "$COMPONENT_INFO" | jq -r '.hasPostgres')" == "true" ] && echo "   - \`DB_USERNAME\` and \`DB_PASSWORD\` for database credentials")
$([ "$(echo "$COMPONENT_INFO" | jq -r '.hasSpringBoot')" == "true" ] && echo "   - \`SPRING_IMAGE_URI\` for the Spring Boot container image")

3. Initialize Terraform:
   \`\`\`
   cd ${OUTPUT_DIR}
   terraform init
   \`\`\`

4. Apply the Terraform configuration:
   \`\`\`
   terraform apply
   \`\`\`

5. To destroy the infrastructure when no longer needed:
   \`\`\`
   terraform destroy
   \`\`\`

## AWS Well-Architected Framework Alignment

The generated infrastructure follows AWS Well-Architected Framework best practices:

1. **Operational Excellence**
   - Infrastructure as Code with Terraform
   - Modular architecture for maintainability
   - Logging and monitoring integration

2. **Security**
   - Least privilege IAM roles and policies
   - Security groups with minimal required access
   - VPC with public/private subnet isolation
   - AWS VPC Flow Logs enabled

3. **Reliability**
   - Multi-AZ deployment
   - Auto scaling capabilities
   - Health checks for automatic recovery

4. **Performance Efficiency**
   - Right-sized resources based on workload requirements
   - Auto scaling based on demand

5. **Cost Optimization**
   - Resources sized according to SCORE specification
   - Pay-per-use model with serverless components where applicable

## Generated Files

- \`${OUTPUT_DIR}/\`: Directory containing Terraform configurations
- \`README.md\`: This documentation file

For more information, refer to the [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/).
EOF