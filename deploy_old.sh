#!/bin/bash
set -e

# Parse command line arguments
usage() {
  echo "Usage: $0 -f <score_file> [-r <aws_region>] [-p <profile>]"
  echo "  -f <score_file>   Path to the SCORE YAML file"
  echo "  -r <aws_region>   AWS region (overrides the one in SCORE file)"
  echo "  -p <profile>      AWS CLI profile to use"
  exit 1
}

SCORE_FILE=""
AWS_REGION=""
AWS_PROFILE=""

while getopts "f:r:p:" opt; do
  case $opt in
    f) SCORE_FILE="$OPTARG" ;;
    r) AWS_REGION="$OPTARG" ;;
    p) AWS_PROFILE="$OPTARG" ;;
    *) usage ;;
  esac
done

if [ -z "$SCORE_FILE" ]; then
  echo "ERROR: SCORE file path is required"
  usage
fi

if [ ! -f "$SCORE_FILE" ]; then
  echo "ERROR: SCORE file not found: $SCORE_FILE"
  exit 1
fi

# Set AWS profile if provided
if [ -n "$AWS_PROFILE" ]; then
  export AWS_PROFILE="$AWS_PROFILE"
  echo "Using AWS profile: $AWS_PROFILE"
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

# Plan Terraform changes
echo "Planning Terraform changes..."
terraform plan -out=tfplan

# Apply Terraform changes
echo "Apply the load balancer and listener resources first......"

terraform apply -target=module.load_balancer tfplan

echo "Applying Terraform changes ..."
terraform apply -auto-approve tfplan

# Output the public URLs for the deployed services
echo ""
echo "====== Deployment Complete ======"
echo "Public URLs for deployed services:"
terraform output -json public_urls | jq -r '.[] | "- \(.name): \(.url)"'

# Output internal URLs if any
INTERNAL_URLS=$(terraform output -json internal_urls 2>/dev/null || echo '[]')
if [ "$INTERNAL_URLS" != "[]" ]; then
  echo ""
  echo "Internal URLs for deployed services:"
  echo "$INTERNAL_URLS" | jq -r '.[] | "- \(.name): \(.url)"'
fi

echo ""
echo "====== Infrastructure Successfully Deployed ======"
echo "Deployment directory: $(pwd)"
echo "To destroy this infrastructure, run: cd $(pwd) && terraform destroy"
