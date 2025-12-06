# eksctl Deployment Configuration

This directory contains the eksctl configuration for deploying an EKS cluster as an alternative to Terraform.

## Overview

eksctl is a simple CLI tool for creating and managing EKS clusters. This configuration provides a faster, more focused way to deploy just the EKS cluster infrastructure without the additional components (RDS, complex networking) that Terraform provides.

## When to Use eksctl vs Terraform

### Use eksctl when:
- You want a **quick cluster setup** for development or testing
- You only need **EKS cluster infrastructure** (VPC, cluster, nodes)
- You prefer **simpler configuration** with fewer moving parts
- You're using an **external database** service
- You want **faster deployment** (typically 15-20 minutes)

### Use Terraform when:
- You need **full infrastructure control** (VPC, EKS, RDS, Secrets Manager, etc.)
- You want **production-ready infrastructure** with all components
- You need an **RDS PostgreSQL database** provisioned automatically
- You prefer **infrastructure as code** with state management
- You want **more customization options** and fine-grained control

## Quick Start

### Prerequisites

1. Install eksctl:
   ```bash
   # macOS
   brew tap weaveworks/tap
   brew install weaveworks/tap/eksctl

   # Linux
   curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin

   # Windows (Chocolatey)
   choco install eksctl
   ```

2. Configure AWS credentials:
   ```bash
   aws configure
   ```

3. Set environment variables (optional):
   ```bash
   export EKS_CLUSTER_NAME=litellm-eks
   export AWS_REGION=us-east-1
   export ENVIRONMENT=production
   ```

### Deploy Cluster

#### Option 1: Interactive (Recommended)
```bash
cd scripts
./deploy.sh infrastructure
# Choose [E] for eksctl
```

#### Option 2: Direct
```bash
cd scripts
./deploy.sh eksctl
```

#### Option 3: Manual eksctl command
```bash
# From project root
envsubst < eksctl/cluster.yaml > /tmp/cluster.yaml
eksctl create cluster -f /tmp/cluster.yaml
```

## Configuration

### Environment Variables

The `cluster.yaml` file uses environment variable substitution:

| Variable | Description | Default |
|----------|-------------|---------|
| `EKS_CLUSTER_NAME` | Name of the EKS cluster | `litellm-eks` |
| `AWS_REGION` | AWS region to deploy to | `us-east-1` |
| `AWS_ACCOUNT_ID` | AWS account ID | Auto-detected |
| `ENVIRONMENT` | Environment tag (dev/staging/prod) | `production` |

### Cluster Configuration

The default configuration includes:

**Cluster:**
- Kubernetes version: 1.31
- OIDC provider: Enabled (required for IRSA)
- CloudWatch logging: Enabled (all log types)
- Public + Private API access

**VPC:**
- CIDR: 10.0.0.0/16
- NAT Gateway: HighlyAvailable (multiple AZs)
- Public and private subnets across 3 AZs

**Node Group:**
- Instance type: t3.xlarge
- Desired capacity: 3 nodes
- Min size: 2 nodes
- Max size: 6 nodes
- Volume: 100 GB gp3
- Private networking: Enabled
- IMDSv2: Required

**IAM Service Accounts (IRSA):**
- `external-secrets` service account in `external-secrets` namespace
- `litellm-sa` service account in `litellm` namespace (for Bedrock access)

**Addons:**
- VPC CNI (latest)
- CoreDNS (latest)
- kube-proxy (latest)
- AWS EBS CSI Driver (latest)

## Customization

### Modify Node Configuration

Edit `cluster.yaml` to customize node settings:

```yaml
managedNodeGroups:
  - name: litellm-ng-1
    instanceType: m5.2xlarge    # Change instance type
    minSize: 3                  # Change min nodes
    maxSize: 10                 # Change max nodes
    desiredCapacity: 5          # Change desired capacity
    volumeSize: 200             # Change volume size
```

### Enable Spot Instances (Cost Optimization)

Uncomment the `instancesDistribution` section in `cluster.yaml`:

```yaml
instancesDistribution:
  maxPrice: 0.20
  instanceTypes: ["t3.xlarge", "t3a.xlarge", "t2.xlarge"]
  onDemandBaseCapacity: 1
  onDemandPercentageAboveBaseCapacity: 30
  spotInstancePools: 3
```

### Use Existing VPC

If you have an existing VPC, uncomment and configure the VPC section:

```yaml
vpc:
  id: "vpc-xxxxx"
  cidr: "10.0.0.0/16"
  subnets:
    private:
      us-east-1a:
        id: "subnet-xxxxx"
      # ... more subnets
```

### Add Fargate Profiles

Uncomment the Fargate section to add serverless workloads:

```yaml
fargateProfiles:
  - name: litellm-fargate
    selectors:
      - namespace: fargate-workloads
```

## Post-Deployment

After cluster creation:

1. **Verify cluster:**
   ```bash
   kubectl get nodes
   kubectl cluster-info
   ```

2. **Check IAM service accounts:**
   ```bash
   eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME
   ```

3. **View cluster details:**
   ```bash
   eksctl get cluster --name $EKS_CLUSTER_NAME
   ```

4. **Deploy applications:**
   ```bash
   cd scripts
   ./deploy.sh all
   ```

## Important Notes

### Database Requirement

**eksctl does NOT create an RDS database.** You must:

1. **Option 1:** Use an external PostgreSQL database
2. **Option 2:** Deploy a PostgreSQL pod in the cluster (not recommended for production)
3. **Option 3:** Use an existing RDS instance

Then configure the database URL:

```bash
aws secretsmanager create-secret \
  --name litellm/database-url \
  --secret-string "postgresql://user:password@your-db-host:5432/litellm" \
  --region $AWS_REGION
```

### AWS Secrets Manager

You still need to create secrets in AWS Secrets Manager:

```bash
cd scripts
./deploy.sh secrets
```

This creates:
- `litellm/master-key` - Master API key
- `litellm/salt-key` - Encryption salt
- `litellm/redis-password` - Redis password

## Cluster Management

### Update Cluster

```bash
# Update node group
eksctl scale nodegroup --cluster=$EKS_CLUSTER_NAME --name=litellm-ng-1 --nodes=5

# Update cluster version
eksctl upgrade cluster --name=$EKS_CLUSTER_NAME --approve

# Update addons
eksctl update addon --name=vpc-cni --cluster=$EKS_CLUSTER_NAME
```

### View Cluster Info

```bash
# Get cluster details
eksctl get cluster --name=$EKS_CLUSTER_NAME

# Get node groups
eksctl get nodegroup --cluster=$EKS_CLUSTER_NAME

# Get IAM service accounts
eksctl get iamserviceaccount --cluster=$EKS_CLUSTER_NAME

# View CloudFormation stacks
aws cloudformation list-stacks --query 'StackSummaries[?contains(StackName, `eksctl-'$EKS_CLUSTER_NAME'`)].{Name:StackName,Status:StackStatus}'
```

### Delete Cluster

```bash
# Using deploy script (recommended)
cd scripts
./deploy.sh infrastructure-destroy-eksctl

# Manual deletion
eksctl delete cluster --name=$EKS_CLUSTER_NAME --wait
```

## Troubleshooting

### Cluster Creation Fails

Check CloudFormation stacks:
```bash
aws cloudformation describe-stack-events \
  --stack-name eksctl-$EKS_CLUSTER_NAME-cluster \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### kubectl Cannot Connect

Update kubeconfig:
```bash
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
```

### Service Account Issues

Check if OIDC provider is configured:
```bash
aws eks describe-cluster --name $EKS_CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" --output text

eksctl utils associate-iam-oidc-provider \
  --cluster=$EKS_CLUSTER_NAME \
  --approve
```

### Node Group Issues

Check node group status:
```bash
eksctl get nodegroup --cluster=$EKS_CLUSTER_NAME

aws eks describe-nodegroup \
  --cluster-name $EKS_CLUSTER_NAME \
  --nodegroup-name litellm-ng-1
```

## Cost Optimization

### For Development/Testing:

1. **Use smaller instances:**
   ```yaml
   instanceType: t3.medium
   ```

2. **Reduce node count:**
   ```yaml
   desiredCapacity: 2
   minSize: 1
   maxSize: 3
   ```

3. **Enable spot instances:**
   ```yaml
   instancesDistribution:
     onDemandBaseCapacity: 0
     onDemandPercentageAboveBaseCapacity: 0
     spotInstancePools: 3
   ```

4. **Single NAT gateway:**
   ```yaml
   nat:
     gateway: Single
   ```

5. **Delete cluster when not in use:**
   ```bash
   eksctl delete cluster --name=$EKS_CLUSTER_NAME
   ```

## Comparison: eksctl vs Terraform

| Feature | eksctl | Terraform |
|---------|--------|-----------|
| **Deployment Time** | 15-20 min | 25-35 min |
| **Configuration Complexity** | Simple YAML | Multiple .tf files |
| **VPC** | ✅ Auto-created | ✅ Custom config |
| **EKS Cluster** | ✅ Full support | ✅ Full support |
| **Node Groups** | ✅ Managed | ✅ Managed |
| **IRSA** | ✅ Built-in | ✅ Manual config |
| **RDS Database** | ❌ Not included | ✅ Included |
| **Secrets Manager** | ❌ Manual | ✅ Automated |
| **Bastion Host** | ❌ Manual | ✅ Optional |
| **State Management** | CloudFormation | Terraform State |
| **Updates** | `eksctl update` | `terraform apply` |
| **GitOps Ready** | ✅ Flux support | ⚠️ Manual setup |
| **Best For** | Dev/Testing | Production |

## Security Best Practices

1. **Enable private networking:**
   ```yaml
   privateNetworking: true
   ```

2. **Disable SSH:**
   ```yaml
   ssh:
     allow: false
   ```

3. **Enable IMDSv2:**
   ```yaml
   # Automatically enabled by default
   ```

4. **Use IAM roles (IRSA):**
   ```yaml
   iam:
     withOIDC: true
   ```

5. **Enable CloudWatch logging:**
   ```yaml
   cloudWatch:
     clusterLogging:
       enableTypes: ["audit", "authenticator", "api"]
   ```

6. **Network policies:**
   ```bash
   # Install Calico or Cilium for network policies
   kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico.yaml
   ```

## Additional Resources

- [eksctl Documentation](https://eksctl.io/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [eksctl Schema Reference](https://eksctl.io/usage/schema/)
- [GitHub: eksctl](https://github.com/weaveworks/eksctl)

## Support

For issues with:
- **eksctl configuration:** Check this README and [eksctl docs](https://eksctl.io/)
- **Application deployment:** See `scripts/README.md`
- **Terraform alternative:** See `terraform/README.md`
