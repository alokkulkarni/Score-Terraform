#!/usr/bin/env python3
import yaml
import json
import os
import sys

def parse_score_file(score_file_path):
    """
    Parse the SCORE yaml file and extract necessary configuration.
    Returns a dict with extracted configuration.
    """
    try:
        with open(score_file_path, 'r') as file:
            score_data = yaml.safe_load(file)
    except Exception as e:
        print(f"Error reading SCORE file: {e}")
        sys.exit(1)
    
    # Extract metadata
    metadata = score_data.get('metadata', {})
    app_name = metadata.get('name', 'app')
    environment = metadata.get('environment', 'dev')
    provider = metadata.get('provider', 'aws')
    region = metadata.get('region', 'us-east-1')
    tags = metadata.get('tags', {})
    
    # Extract workloads
    workloads = score_data.get('workloads', {})
    
    # Container workloads (services)
    container_workloads = {}
    for name, workload in workloads.items():
        if workload.get('type') == 'container':
            container_workloads[name] = {
                'image': workload.get('image', ''),
                'cpu': workload.get('resources', {}).get('cpu', 256),
                'memory': workload.get('resources', {}).get('memory', 512),
                'ports': workload.get('ports', []),
                'replicas': workload.get('replicas', 1),
                'environment': workload.get('environment', {}),
                'routes': workload.get('routes', []),
                'healthCheck': workload.get('healthCheck', {}),
                'dependsOn': workload.get('dependsOn', [])
            }
    
    # Database workloads
    database_workloads = {}
    for name, workload in workloads.items():
        if workload.get('type') == 'database':
            database_workloads[name] = {
                'engine': workload.get('engine', 'postgres'),
                'version': workload.get('version', '13.4'),
                'resources': workload.get('resources', {}),
                'backup': workload.get('backup', {}),
                'credentials': workload.get('credentials', {})
            }
    
    # Extract resources
    resources = score_data.get('resources', {})
    networking = resources.get('networking', {})
    loadbalancer = resources.get('loadbalancer', {})
    dns = resources.get('dns', {})
    
    # Prepare output
    config = {
        'app_name': app_name,
        'environment': environment,
        'provider': provider,
        'region': region,
        'tags': tags,
        'container_workloads': container_workloads,
        'database_workloads': database_workloads,
        'networking': networking,
        'loadbalancer': loadbalancer,
        'dns': dns
    }
    
    return config

def generate_tf_vars(config, output_file='terraform.tfvars.json'):
    """
    Generate Terraform variables file from the parsed configuration.
    """
    tf_vars = {
        'app_name': config['app_name'],
        'environment': config['environment'],
        'aws_region': config['region'],
        'tags': config['tags'],
        
        # Network configuration
        'vpc_cidr': config['networking'].get('cidr', '10.0.0.0/16'),
        'public_subnet_count': config['networking'].get('subnets', {}).get('public', 2),
        'private_subnet_count': config['networking'].get('subnets', {}).get('private', 2),
        
        # Load balancer configuration
        'public_lb_enabled': config['loadbalancer'].get('public', {}).get('enabled', False),
        'public_lb_cert_arn': config['loadbalancer'].get('public', {}).get('tlsCertificate', ''),
        'internal_lb_enabled': config['loadbalancer'].get('internal', {}).get('enabled', False),
        'internal_lb_cert_arn': config['loadbalancer'].get('internal', {}).get('tlsCertificate', ''),
        
        # DNS configuration
        'domain_name': config['dns'].get('domain', ''),
        'hosted_zone_id': config['dns'].get('hostedZoneId', ''),
        
        # Database configuration
        'databases': [
            {
                'name': name,
                'engine': db['engine'],
                'version': db['version'],
                'instance_class': db['resources'].get('instance', 'db.t3.small'),
                'allocated_storage': db['resources'].get('storage', 20),
                'backup_retention_period': db['backup'].get('retention', 7),
                'username': db['credentials'].get('username', 'admin'),
                'password': db['credentials'].get('password', 'Password123!')
            }
            for name, db in config['database_workloads'].items()
        ],
        
        # Container services configuration
        'services': [
            {
                'name': name,
                'image': svc['image'],
                'cpu': svc['cpu'],
                'memory': svc['memory'],
                'container_port': svc['ports'][0]['port'] if svc['ports'] else 80,
                'protocol': svc['ports'][0]['protocol'] if svc['ports'] else 'http',
                'desired_count': svc['replicas'],
                'health_check_path': svc['healthCheck'].get('path', '/'),
                'health_check_initial_delay': svc['healthCheck'].get('initialDelaySeconds', 30),
                'health_check_interval': svc['healthCheck'].get('periodSeconds', 10),
                'environment_variables': svc['environment'],
                'public_routes': [
                    {
                        'host': route['host'],
                        'path': route['path'],
                        'port': route['port']
                    }
                    for route in svc['routes'] if route.get('type') == 'public'
                ],
                'internal_routes': [
                    {
                        'host': route['host'],
                        'path': route['path'],
                        'port': route['port']
                    }
                    for route in svc['routes'] if route.get('type') == 'internal'
                ],
                'depends_on': svc['dependsOn']
            }
            for name, svc in config['container_workloads'].items()
        ]
    }
    
    # Write to file
    try:
        with open(output_file, 'w') as f:
            json.dump(tf_vars, f, indent=2)
        print(f"Terraform variables written to {output_file}")
    except Exception as e:
        print(f"Error writing Terraform variables: {e}")
        sys.exit(1)
    
    return tf_vars

def main():
    if len(sys.argv) < 2:
        print("Usage: python parse_score.py <score_file_path>")
        sys.exit(1)
    
    score_file_path = sys.argv[1]
    config = parse_score_file(score_file_path)
    generate_tf_vars(config)
    
    # Export variables for other scripts
    with open('score_config.json', 'w') as f:
        json.dump(config, f, indent=2)
    
    print("SCORE file successfully parsed and configuration generated.")

if __name__ == "__main__":
    main()
