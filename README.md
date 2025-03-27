# SCORE Infrastructure Deployment Tool

This tool automates the deployment of infrastructure described in a SCORE file using Terraform. It parses the SCORE YAML file and creates the necessary Terraform configuration to deploy the infrastructure and workloads in AWS using a phased approach to handle resource dependencies properly.

## Prerequisites

- Python 3.6+
- Terraform 1.0.0+
- AWS CLI
- jq

Python packages:
- pyyaml

Install Python dependencies:
```bash
pip install pyyaml
```

## Project Structure

```
.
├── deploy_score.sh        # Master script
├── parse_score.py         # Python script to parse SCORE file
├── setup_terraform.sh     # Script to setup Terraform configuration
├── deploy.sh              # Script to deploy the infrastructure in phases
├── destroy.sh             # Script to destroy the infrastructure in phases
├── modules/               # Terraform modules
│   ├── vpc/               # VPC module
│   ├── security/          # Security groups module
│   ├── database/          # Database module
│   ├── load_balancer/     # Load balancer module
│   ├── ecs/               # ECS module
│   └── dns/               # DNS module
├── main.tf                # Main Terraform configuration
├── variables.tf           # Terraform variables
└── outputs.tf             # Terraform outputs
```

## How to Use

1. Make sure you have all the prerequisites installed.
2. Clone this repository.
3. Make the scripts executable:
   ```bash
   chmod +x *.sh parse_score.py
   ```
4. Run the master script:
   ```bash
   ./deploy_score.sh -f path/to/score.yaml [-r aws-region] [-p aws-profile] [-y]
   ```

### Arguments for Deployment

- `-f` (required): Path to the SCORE YAML file
- `-r` (optional): AWS region (overrides the one in SCORE file)
- `-p` (optional): AWS CLI profile to use
- `-y` (optional): Skip confirmation prompts (auto-approve all phases)

## What it Does

1. Parses the SCORE file to extract metadata, workloads, and resources.
2. Creates the necessary Terraform configuration files.
3. Deploys the infrastructure in multiple phases to handle resource dependencies:
   - Network infrastructure (VPC)
   - Database resources
   - Load balancer resources
   - SSL certificates and validation
   - Listeners that depend on certificates
   - Target groups for services
   - Listener rules
   - ECS services
   - Any remaining resources
4. Outputs the public and internal URLs for the deployed services.

## Multi-Phase Deployment

The tool uses a multi-phase deployment approach to handle Terraform's limitation with `for_each` expressions that depend on resource attributes determined at apply time. Each phase:

1. Creates a Terraform plan focusing on specific resources
2. Shows the plan for review
3. Asks for confirmation (unless `-y` is used)
4. Applies the changes
5. Moves to the next phase

This approach ensures that resources are created in the correct order, with dependencies established first.

## Infrastructure Components

The tool deploys the following infrastructure components:

- VPC with public and private subnets
- Security groups for load balancers, ECS services, and databases
- RDS PostgreSQL database instances
- Application Load Balancers (public and internal)
- ECS Fargate services
- Route53 DNS records
- TLS certificates via AWS ACM

## Example

```bash
./deploy_score.sh -f score.yaml -r eu-west-2 -p myawsprofile
```

This will deploy the infrastructure described in `score.yaml` to the `eu-west-2` region using the AWS profile `myawsprofile`.

## Cleanup

To destroy the deployed infrastructure safely, use the provided destroy script:

```bash
./destroy.sh -d <deployment_directory> [-p aws-profile] [-y]
```

Where:
- `-d` (required): Path to the deployment directory
- `-p` (optional): AWS CLI profile to use
- `-y` (optional): Skip confirmation prompts

The destroy script removes resources in the reverse order of creation to properly handle dependencies.

Alternatively, you can use the command shown at the end of the deployment process:

```bash
./deploy.sh -D -d <deployment_directory> [-y]
```

## Limitations

- Currently only supports AWS as the provider
- Only supports PostgreSQL as the database engine
- Only supports container workloads on ECS Fargate
- Does not support all possible SCORE file configurations
- Target group health checks expect services to have a health endpoint

## Troubleshooting

If you encounter errors related to resource dependencies:

1. Try rerunning the deployment with more specific targets using:
   ```bash
   terraform apply -target=<resource_name>
   ```
2. Check the AWS Console to see if resources were partially created
3. Use the destroy script to clean up resources before trying again

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
