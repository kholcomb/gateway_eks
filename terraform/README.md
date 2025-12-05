# LiteLLM AWS Infrastructure (Terraform)

This Terraform configuration provisions the complete AWS infrastructure required to run LiteLLM on Amazon EKS.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                    VPC                                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │  Public Subnet  │  │  Public Subnet  │  │  Public Subnet  │              │
│  │    (AZ-1)       │  │    (AZ-2)       │  │    (AZ-3)       │              │
│  │   NAT Gateway   │  │   NAT Gateway   │  │   NAT Gateway   │              │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘              │
│           │                    │                    │                        │
│  ┌────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐              │
│  │ Private Subnet  │  │ Private Subnet  │  │ Private Subnet  │              │
│  │    (AZ-1)       │  │    (AZ-2)       │  │    (AZ-3)       │              │
│  │   EKS Nodes     │  │   EKS Nodes     │  │   EKS Nodes     │              │
│  │   [Bastion]     │  │                 │  │                 │              │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘              │
│           │                    │                    │                        │
│  ┌────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐              │
│  │Database Subnet  │  │Database Subnet  │  │Database Subnet  │              │
│  │    (AZ-1)       │  │    (AZ-2)       │  │    (AZ-3)       │              │
│  │                 │  │   RDS Primary   │  │   RDS Standby   │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         EKS Control Plane                             │   │
│  │                    (AWS-managed, Multi-AZ)                            │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           AWS Services                                       │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐                 │
│  │ Secrets Manager│  │    Bedrock     │  │   CloudWatch   │                 │
│  │  - Master Key  │  │ Claude, Llama  │  │   VPC Logs     │                 │
│  │  - Salt Key    │  │ Mistral, etc.  │  │  Cluster Logs  │                 │
│  │  - Redis Pass  │  │                │  │  RDS Metrics   │                 │
│  │  - DB URL      │  │                │  │                │                 │
│  └────────────────┘  └────────────────┘  └────────────────┘                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform >= 1.5.0
- kubectl
- helm

## Modules

| Module | Description |
|--------|-------------|
| `vpc` | VPC with public, private, and database subnets across 3 AZs |
| `eks` | EKS cluster with managed node groups, OIDC provider, and EBS CSI driver |
| `rds` | PostgreSQL RDS with Multi-AZ, encryption, and AWS-managed password |
| `secrets` | Secrets Manager secrets for LiteLLM (master key, salt, redis password) |
| `iam` | IRSA roles for LiteLLM (Bedrock access) and External Secrets Operator |
| `bastion` | Optional EC2 bastion for testing access via SSM Session Manager |

## Quick Start

### 1. Configure Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize and Plan

```bash
terraform init
terraform plan
```

### 3. Apply Infrastructure

```bash
terraform apply
```

### 4. Configure kubectl

```bash
# Get the command from Terraform output
terraform output configure_kubectl

# Run it:
aws eks update-kubeconfig --name litellm-eks --region us-east-1
```

### 5. Deploy Applications

After infrastructure is provisioned, run the Kubernetes deployment:

```bash
# Set environment variables from Terraform output
eval "$(terraform output -raw deploy_script_env_vars)"

# Run the deployment script
../scripts/deploy.sh all
```

## Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `environment` | Environment name | `prod` |
| `eks_cluster_version` | Kubernetes version | `1.31` |
| `rds_instance_class` | RDS instance type | `db.t3.medium` |
| `rds_multi_az` | Enable Multi-AZ | `true` |
| `create_bastion` | Create bastion EC2 | `false` |

### Node Groups

Configure node groups in `terraform.tfvars`:

```hcl
eks_node_groups = {
  default = {
    instance_types = ["m6i.large", "m5.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    desired_size   = 3
    min_size       = 2
    max_size       = 6
    labels         = {}
    taints         = []
  }
}
```

### Bedrock Models

Configure allowed Bedrock models:

```hcl
bedrock_model_arns = [
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0",
  # Add more models as needed
]
```

## Testing with the Bastion

The bastion provides a way to test OpenWebUI and other services **without exposing them to the internet**. It's a simple EC2 in a private subnet that you access via SSM Session Manager, then use `kubectl port-forward` to access services locally.

If `create_bastion = true`:

```bash
# Get the SSM connect command
terraform output bastion_ssm_connect_command

# Connect via SSM Session Manager
aws ssm start-session --target i-xxxxxxxxxxxx --region us-east-1

# Once connected, use pre-configured aliases:
llm-ui         # Port-forward OpenWebUI to localhost:8080
llm-grafana    # Port-forward Grafana to localhost:3000
llm-prometheus # Port-forward Prometheus to localhost:9090
llm-jaeger     # Port-forward Jaeger to localhost:16686

# Then access via your browser (SSM port forwarding or local browser if using SSM with port forwarding)
```

For browser access from your local machine, use SSM port forwarding:
```bash
aws ssm start-session --target i-xxxxxxxxxxxx \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"],"host":["localhost"]}'
```

## Security Considerations

- **IRSA**: Uses IAM Roles for Service Accounts (no static credentials in pods)
- **AWS-managed RDS password**: Password automatically rotated by AWS
- **Secrets encryption**: All secrets encrypted with KMS
- **VPC Flow Logs**: Network traffic logging enabled
- **IMDSv2**: Required on EC2 instances
- **Private subnets**: Workloads run in private subnets
- **No public database**: RDS only accessible from within VPC

## Outputs

Key outputs after `terraform apply`:

```bash
# EKS cluster information
terraform output eks_cluster_endpoint
terraform output eks_cluster_name

# RDS connection details
terraform output rds_endpoint
terraform output rds_master_user_secret_arn

# IAM roles for IRSA
terraform output litellm_bedrock_role_arn
terraform output external_secrets_role_arn

# Bastion access
terraform output bastion_ssm_connect_command
```

## Cost Optimization

For non-production environments:

```hcl
# Use single NAT gateway
single_nat_gateway = true

# Disable Multi-AZ RDS
rds_multi_az = false

# Use smaller instances
rds_instance_class = "db.t3.small"
eks_node_groups = {
  default = {
    instance_types = ["t3.medium"]
    capacity_type  = "SPOT"  # Use spot instances
    desired_size   = 2
    min_size       = 1
    max_size       = 4
  }
}
```

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

**Warning**: This will delete all resources including the RDS database. Make sure to backup any important data first.

## Remote State

For production, configure remote state in S3:

```hcl
# In main.tf, uncomment and configure:
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "litellm/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-locks"
}
```

Create the S3 bucket and DynamoDB table before initializing:

```bash
aws s3 mb s3://your-terraform-state-bucket --region us-east-1
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```
