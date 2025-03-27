#!/bin/bash
set -e

# Parse command line arguments
usage() {
  echo "Usage: $0 -d <deployment_dir> [-p <profile>] [-y]"
  echo "  -d <deployment_dir> Path to the deployment directory"
  echo "  -p <profile>        AWS CLI profile to use"
  echo "  -y                  Skip confirmation prompts (auto-approve all phases)"
  exit 1
}

DEPLOY_DIR=""
AWS_PROFILE=""
AUTO_APPROVE=0

while getopts "d:p:y" opt; do
  case $opt in
    d) DEPLOY_DIR="$OPTARG" ;;
    p) AWS_PROFILE="$OPTARG" ;;
    y) AUTO_APPROVE=1 ;;
    *) usage ;;
  esac
done

if [ -z "$DEPLOY_DIR" ]; then
  echo "ERROR: Deployment directory is required"
  usage
fi

# Set AWS profile if provided
if [ -n "$AWS_PROFILE" ]; then
  export AWS_PROFILE="$AWS_PROFILE"
  echo "Using AWS profile: $AWS_PROFILE"
fi

# Function to clean up plan files
cleanup_plan_files() {
  rm -f tf-destroy-*.plan
}

# Register cleanup function for normal script exit
trap cleanup_plan_files EXIT

# Function to destroy resources with confirmation
destroy_with_confirmation() {
  local target=$1
  local phase_name=$2
  local plan_file="tf-destroy-$(echo "$phase_name" | tr -d '[:space:][:punct:]').plan"
  
  echo -e "\n====== $phase_name ======"
  
  # Always show and save the plan
  echo "Planning destruction for $phase_name..."
  terraform plan -destroy -target=$target -out="$plan_file"
  
  # If not auto-approve, ask for confirmation
  if [ $AUTO_APPROVE -eq 0 ]; then
    echo -en "\nDo you want to destroy these resources? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      echo "Destroying resources for $phase_name..."
      terraform apply "$plan_file"
    else
      echo "Skipping destruction for $phase_name."
      return 1
    fi
  else
    echo "Auto-approving destruction for $phase_name..."
    terraform apply "$plan_file"
  fi
  
  # Clean up the plan file after applying
  rm -f "$plan_file"
  
  return 0
}

# Check if the directory exists
if [ ! -d "$DEPLOY_DIR" ]; then
  echo "ERROR: Deployment directory not found: $DEPLOY_DIR"
  exit 1
fi

# Change to the deployment directory
cd "$DEPLOY_DIR"

echo -e "\n====== Beginning Multi-Phase Destruction ======"
echo "Working in directory: $(pwd)"

# Verify that we're in the right place
if [ ! -f "terraform.tfstate" ]; then
  echo "ERROR: terraform.tfstate not found in $(pwd)"
  echo "Are you sure this is a valid terraform deployment directory?"
  exit 1
fi

# Multi-phase destruction in reverse order of creation
echo -e "\n====== Starting Multi-Phase Destruction ======"

# Phase 1: First destroy ECS services (they depend on many other resources)
destroy_with_confirmation "module.ecs.aws_ecs_service.services" "Phase 1: Destroying ECS services" || exit 1

# Phase 2: Destroy listener rules
destroy_with_confirmation "module.ecs.aws_lb_listener_rule.internal" "Phase 2a: Destroying internal listener rules" || exit 1
destroy_with_confirmation "module.ecs.aws_lb_listener_rule.public" "Phase 2b: Destroying public listener rules" || exit 1

# Phase 3: Destroy target groups
destroy_with_confirmation "module.ecs.aws_lb_target_group.internal" "Phase 3a: Destroying internal target groups" || exit 1
destroy_with_confirmation "module.ecs.aws_lb_target_group.public" "Phase 3b: Destroying public target groups" || exit 1

# Phase 4: Destroy HTTPS listeners
destroy_with_confirmation "aws_lb_listener.internal_https" "Phase 4a: Destroying internal HTTPS listener" || exit 1
destroy_with_confirmation "aws_lb_listener.public_https" "Phase 4b: Destroying public HTTPS listener" || exit 1

# Phase 5: Destroy certificate validations
destroy_with_confirmation "aws_acm_certificate_validation.internal" "Phase 5a: Destroying internal certificate validation" || exit 1
destroy_with_confirmation "aws_acm_certificate_validation.public" "Phase 5b: Destroying public certificate validation" || exit 1

# Phase 6: Destroy certificates
destroy_with_confirmation "aws_acm_certificate.internal" "Phase 6a: Destroying internal SSL certificate" || exit 1
destroy_with_confirmation "aws_acm_certificate.public" "Phase 6b: Destroying public SSL certificate" || exit 1

# Phase 7: Destroy load balancer resources
destroy_with_confirmation "module.load_balancer" "Phase 7: Destroying load balancer resources" || exit 1

# Phase 8: Destroy database resources
destroy_with_confirmation "module.database" "Phase 8: Destroying database resources" || exit 1

# Phase 9: Destroy ECS cluster and task definitions
destroy_with_confirmation "module.ecs" "Phase 9: Destroying remaining ECS resources" || exit 1

# Phase 10: Destroy network infrastructure (VPC should be last as other resources depend on it)
destroy_with_confirmation "module.vpc" "Phase 10: Destroying network infrastructure" || exit 1

# Final phase: Destroy any remaining resources
echo -e "\n====== Final Phase: Destroying any remaining resources ======"
echo "Planning final destruction..."
terraform plan -destroy -out=tf-destroy-final.plan

if [ $AUTO_APPROVE -eq 0 ]; then
  echo -en "\nDo you want to destroy any remaining resources? (y/n): "
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Destroying remaining resources..."
    terraform apply tf-destroy-final.plan
  else
    echo "Skipping final resource destruction."
    exit 1
  fi
else
  echo "Auto-approving final destruction..."
  terraform apply tf-destroy-final.plan
fi

# Clean up the final plan file
rm -f tf-destroy-final.plan

echo -e "\n====== Infrastructure Successfully Destroyed ======"
echo "All resources have been destroyed."