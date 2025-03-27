#!/bin/bash
set -e

# Parse command line arguments
usage() {
  echo "Usage: $0 -f <score_file> [-r <aws_region>] [-p <profile>] [-y] [-d <deployment_dir>]"
  echo "  -f <score_file>     Path to the SCORE YAML file"
  echo "  -r <aws_region>     AWS region (overrides the one in SCORE file)"
  echo "  -p <profile>        AWS CLI profile to use"
  echo "  -y                  Skip confirmation prompts (auto-approve all phases)"
  echo "  -d <deployment_dir> Path to existing deployment directory (for destroy)"
  echo "  -D                  Destroy the infrastructure instead of deploying"
  exit 1
}

SCORE_FILE=""
AWS_REGION=""
AWS_PROFILE=""
AUTO_APPROVE=0
DEPLOY_DIR=""
DESTROY_MODE=0

while getopts "f:r:p:yd:D" opt; do
  case $opt in
    f) SCORE_FILE="$OPTARG" ;;
    r) AWS_REGION="$OPTARG" ;;
    p) AWS_PROFILE="$OPTARG" ;;
    y) AUTO_APPROVE=1 ;;
    d) DEPLOY_DIR="$OPTARG" ;;
    D) DESTROY_MODE=1 ;;
    *) usage ;;
  esac
done

# Set AWS profile if provided
if [ -n "$AWS_PROFILE" ]; then
  export AWS_PROFILE="$AWS_PROFILE"
  echo "Using AWS profile: $AWS_PROFILE"
fi

# Function to clean up plan files
cleanup_plan_files() {
  rm -f tf-plan-*.plan
}

# Register cleanup function for normal script exit
trap cleanup_plan_files EXIT

# Function to apply terraform changes with optional confirmation
apply_with_confirmation() {
  local target=$1
  local phase_name=$2
  local plan_file="tf-plan-$(echo "$phase_name" | tr -d '[:space:][:punct:]').plan"
  
  echo -e "\n====== $phase_name ======"
  
  # Always show and save the plan
  echo "Planning changes for $phase_name..."
  terraform plan -target=$target -out="$plan_file"
  
  # If not auto-approve, ask for confirmation
  if [ $AUTO_APPROVE -eq 0 ]; then
    echo -en "\nDo you want to apply these changes? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      echo "Applying changes for $phase_name..."
      terraform apply "$plan_file"
    else
      echo "Skipping $phase_name application."
      return 1
    fi
  else
    echo "Auto-approving changes for $phase_name..."
    terraform apply "$plan_file"
  fi
  
  # Clean up the plan file after applying
  rm -f "$plan_file"
  
  return 0
}

# Function to destroy infrastructure with confirmation
destroy_with_confirmation() {
  local dir=$1
  
  # Check if the directory exists
  if [ ! -d "$dir" ]; then
    echo "ERROR: Deployment directory not found: $dir"
    exit 1
  fi
  
  # Change to the deployment directory
  cd "$dir"
  
  echo -e "\n====== Destroying Infrastructure ======"
  
  # Create a destroy plan
  echo "Creating destroy plan..."
  terraform plan -destroy -out=tf-destroy.plan
  
  # Ask for confirmation
  if [ $AUTO_APPROVE -eq 0 ]; then
    echo -e "\nWARNING: This will destroy all resources created by this deployment."
    echo -en "\nAre you sure you want to destroy the infrastructure? (type 'yes' to confirm): "
    read -r response
    if [[ "$response" == "yes" ]]; then
      echo "Destroying infrastructure..."
      terraform apply tf-destroy.plan
      echo -e "\nInfrastructure successfully destroyed."
    else
      echo "Destruction cancelled."
      exit 1
    fi
  else
    echo "Auto-approving destruction..."
    terraform apply tf-destroy.plan
    echo -e "\nInfrastructure successfully destroyed."
  fi
  
  # Clean up the destroy plan file
  rm -f tf-destroy.plan
}

# Check if we're in destroy mode
if [ $DESTROY_MODE -eq 1 ]; then
  if [ -z "$DEPLOY_DIR" ]; then
    echo "ERROR: Deployment directory (-d) is required for destroy mode"
    usage
  fi
  
  destroy_with_confirmation "$DEPLOY_DIR"
  exit 0
fi

# Proceed with deployment
if [ -z "$SCORE_FILE" ]; then
  echo "ERROR: SCORE file path is required for deployment"
  usage
fi

if [ ! -f "$SCORE_FILE" ]; then
  echo "ERROR: SCORE file not found: $SCORE_FILE"
  exit 1
fi

# Create deployment directory
DEPLOY_DIR="score-deployment-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEPLOY_DIR"
cp "$SCORE_FILE" "$DEPLOY_DIR/score.yaml"
cd "$DEPLOY_DIR"

echo "====== Setting up deployment environment ======"

# Parse SCORE file
echo "Parsing SCORE file..."
python ../parse_score.py score.yaml

# Setup Terraform configuration
echo "Setting up Terraform configuration..."
bash ../setup_terraform.sh

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# If AWS region is provided, override the one in the SCORE file
if [ -n "$AWS_REGION" ]; then
  echo "Overriding AWS region to: $AWS_REGION"
  TF_VAR_FILE=$(mktemp)
  jq ".aws_region = \"$AWS_REGION\"" terraform.tfvars.json > "$TF_VAR_FILE"
  mv "$TF_VAR_FILE" terraform.tfvars.json
fi

# Multi-phase deployment to handle for_each dependencies
echo -e "\n====== Starting Multi-Phase Deployment ======"

# Phase 1: Create network infrastructure
apply_with_confirmation "module.vpc" "Phase 1: Creating network infrastructure" || exit 1

# Phase 2: Create database resources
apply_with_confirmation "module.database" "Phase 2: Creating database resources" || exit 1

# Phase 3: Create load balancer and listeners
apply_with_confirmation "module.load_balancer" "Phase 3: Creating load balancer resources" || exit 1

# Phase 4: Create SSL certificates and validation resources
apply_with_confirmation "aws_acm_certificate.public" "Phase 4a: Creating public SSL certificate" || exit 1
apply_with_confirmation "aws_acm_certificate.internal" "Phase 4b: Creating internal SSL certificate" || exit 1
apply_with_confirmation "aws_acm_certificate_validation.public" "Phase 4c: Validating public SSL certificate" || exit 1
apply_with_confirmation "aws_acm_certificate_validation.internal" "Phase 4d: Validating internal SSL certificate" || exit 1

# Phase 5: Create listeners that depend on certificates
apply_with_confirmation "aws_lb_listener.public_https" "Phase 5a: Creating public HTTPS listener" || exit 1
apply_with_confirmation "aws_lb_listener.internal_https" "Phase 5b: Creating internal HTTPS listener" || exit 1

# Phase 6: Create target groups for the services
apply_with_confirmation "module.ecs.aws_lb_target_group.public" "Phase 6a: Creating public target groups" || exit 1
apply_with_confirmation "module.ecs.aws_lb_target_group.internal" "Phase 6b: Creating internal target groups" || exit 1

# Phase 7: Create listener rules
apply_with_confirmation "module.ecs.aws_lb_listener_rule.public" "Phase 7a: Creating public listener rules" || exit 1
apply_with_confirmation "module.ecs.aws_lb_listener_rule.internal" "Phase 7b: Creating internal listener rules" || exit 1

# Phase 8: Create ECS services
apply_with_confirmation "module.ecs.aws_ecs_service.services" "Phase 8: Creating ECS services" || exit 1

# Final phase: Apply all remaining resources
echo -e "\n====== Final Phase: Applying any remaining configurations ======"
echo "Planning final changes..."
terraform plan -out=tf-final.plan

if [ $AUTO_APPROVE -eq 0 ]; then
  echo -en "\nDo you want to apply these final changes? (y/n): "
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Applying final changes..."
    terraform apply tf-final.plan
  else
    echo "Skipping final changes. Deployment may be incomplete."
    exit 1
  fi
else
  echo "Auto-approving final changes..."
  terraform apply tf-final.plan
fi

# Clean up the final plan file
rm -f tf-final.plan

# Output the public URLs for the deployed services
echo -e "\n====== Deployment Complete ======"
echo "Public URLs for deployed services:"
terraform output -json public_urls | jq -r '.[] | "- \(.name): \(.url)"' 2>/dev/null || echo "No public URLs available"

# Output internal URLs if any
INTERNAL_URLS=$(terraform output -json internal_urls 2>/dev/null || echo '[]')
if [ "$INTERNAL_URLS" != "[]" ]; then
  echo -e "\nInternal URLs for deployed services:"
  echo "$INTERNAL_URLS" | jq -r '.[] | "- \(.name): \(.url)"' 2>/dev/null || echo "No internal URLs available"
fi

echo -e "\n====== Infrastructure Successfully Deployed ======"
echo "Deployment directory: $(pwd)"
echo "To destroy this infrastructure, run:"
echo "./deploy.sh -D -d $(pwd) [-y]"