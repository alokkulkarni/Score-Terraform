#!/bin/bash
set -e

# Master script to deploy infrastructure from SCORE file

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

# Check for required dependencies
check_dependencies() {
  echo "Checking dependencies..."
  for cmd in python3 terraform jq aws; do
    if ! command -v $cmd &> /dev/null; then
      echo "ERROR: $cmd is required but not installed"
      exit 1
    fi
  done
  
  # Check Python dependencies
  python3 -c "import yaml, json" 2>/dev/null || {
    echo "ERROR: Python modules 'yaml' and 'json' are required"
    echo "Install them using: pip install pyyaml"
    exit 1
  }
  
  # Check Terraform version
  TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
  if [[ "$(echo -e "1.0.0\n$TF_VERSION" | sort -V | head -n1)" == "1.0.0" ]]; then
    echo "Terraform version $TF_VERSION detected"
  else
    echo "ERROR: Terraform version 1.0.0 or higher is required (found $TF_VERSION)"
    exit 1
  fi
  
  echo "All dependencies are satisfied"
}

# Make scripts executable
make_scripts_executable() {
  chmod +x parse_score.py
  chmod +x setup_terraform.sh
  chmod +x deploy.sh
}

# Main execution
echo "====== SCORE Infrastructure Deployment ======"
echo "SCORE file: $SCORE_FILE"
[ -n "$AWS_REGION" ] && echo "AWS region: $AWS_REGION"
[ -n "$AWS_PROFILE" ] && echo "AWS profile: $AWS_PROFILE"
echo ""

check_dependencies

make_scripts_executable

echo "Starting deployment..."
./deploy.sh -f "$SCORE_FILE" ${AWS_REGION:+-r "$AWS_REGION"} ${AWS_PROFILE:+-p "$AWS_PROFILE"}

echo "====== Deployment Process Complete ======"
