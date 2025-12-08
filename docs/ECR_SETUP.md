# ECR Setup and Usage Guide

This guide covers the Elastic Container Registry (ECR) setup for storing and managing container images used in the LiteLLM EKS deployment.

## Overview

The infrastructure creates two ECR repositories with different policies:

1. **Infrastructure Repository** (`infrastructure`)
   - For core platform images (LiteLLM, OpenWebUI)
   - Immutable tags for security
   - Keeps 20 tagged versions
   - 7-day retention for untagged images

2. **Deployments Repository** (`deployments`)
   - For application workloads (MCP servers, custom apps)
   - Mutable tags for development flexibility
   - Keeps 10 tagged versions
   - 3-day retention for untagged images (aggressive cleanup)

## Repository Structure

```
<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/
├── infrastructure/          # Platform images (IMMUTABLE tags)
│   ├── litellm:v1.80.5
│   ├── litellm:v1.81.0
│   ├── openwebui:latest
│   └── openwebui:v0.1.0
└── deployments/            # Application images (MUTABLE tags)
    ├── mcp-servers:github-v1.0.0
    ├── mcp-servers:slack-latest
    └── custom-app:dev
```

## Features

- **Automatic Vulnerability Scanning**: Enabled on push for all images
- **KMS Encryption**: All images encrypted at rest with KMS
- **Lifecycle Policies**: Automatic cleanup of old/untagged images
- **IAM Integration**: IRSA roles for cluster access, separate policy for CI/CD

## Deployment

### Using Terraform

The ECR repositories are created automatically when deploying infrastructure:

```bash
cd terraform

# ECR is enabled by default
terraform apply

# To disable ECR creation
terraform apply -var="create_ecr_repositories=false"
```

### Configuration Options

In `terraform.tfvars`:

```hcl
# Enable/disable ECR
create_ecr_repositories = true

# Customize infrastructure repository
ecr_infrastructure_repository = {
  name                    = "infrastructure"
  tag_mutability          = "IMMUTABLE"
  lifecycle_tag_count     = 20
  lifecycle_untagged_days = 7
}

# Customize deployments repository
ecr_deployments_repository = {
  name                    = "deployments"
  tag_mutability          = "MUTABLE"
  lifecycle_tag_count     = 10
  lifecycle_untagged_days = 3
}

# Enable scanning and encryption
ecr_scan_on_push      = true
ecr_enable_encryption = true
```

## Authentication and Access

### For EKS Nodes (Pull Only)

EKS nodes automatically have read-only access to ECR through the `AmazonEC2ContainerRegistryReadOnly` managed policy. No additional configuration needed.

### For CI/CD (Push and Pull)

An IAM policy is created for CI/CD systems to push and pull images:

```bash
# Get the policy ARN from Terraform output
terraform output ecr_push_pull_policy_arn

# Attach to your CI/CD IAM role or user
aws iam attach-role-policy \
  --role-name your-cicd-role \
  --policy-arn $(terraform output -raw ecr_push_pull_policy_arn)
```

The policy includes:
- `ecr:GetAuthorizationToken` - Authenticate to ECR
- `ecr:BatchCheckLayerAvailability` - Check if layers exist
- `ecr:GetDownloadUrlForLayer` - Pull images
- `ecr:BatchGetImage` - Pull images
- `ecr:PutImage` - Push images
- `ecr:InitiateLayerUpload` - Push images
- `ecr:UploadLayerPart` - Push images
- `ecr:CompleteLayerUpload` - Push images

### Docker Login

```bash
# Get login command from Terraform output
terraform output -raw ecr_login_command

# Or manually construct it
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

## Building and Pushing Images

### Infrastructure Images

For core platform images with immutable tags:

```bash
# Build LiteLLM image
docker build -t litellm:v1.80.5 /path/to/litellm

# Tag for ECR
docker tag litellm:v1.80.5 \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/infrastructure:litellm-v1.80.5

# Push to ECR
docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/infrastructure:litellm-v1.80.5
```

**Note**: Infrastructure repository uses IMMUTABLE tags. You cannot overwrite an existing tag like `litellm-v1.80.5`. Use a new version number for each push.

### Deployment Images

For application workloads with mutable tags:

```bash
# Build MCP server image
docker build -t mcp-github:latest /path/to/mcp-github

# Tag for ECR
docker tag mcp-github:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/deployments:mcp-github-latest

# Push to ECR (can overwrite existing tags)
docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/deployments:mcp-github-latest
```

## Using Images in Kubernetes

### Update Deployment Manifests

Reference ECR images in your Kubernetes manifests:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm
  namespace: litellm
spec:
  template:
    spec:
      containers:
      - name: litellm
        image: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/infrastructure:litellm-v1.80.5
```

### Update Helm Values

For LiteLLM (`helm-values/litellm-values.yaml`):

```yaml
image:
  repository: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/infrastructure
  tag: litellm-v1.80.5
```

For MCP servers (`docs/mcp/examples/mcp-server-template.yaml`):

```yaml
spec:
  containers:
  - name: mcp-server
    image: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/deployments:mcp-github-v1.0.0
```

## OPA Gatekeeper Policy

The allowed-repos OPA policy automatically permits images from your ECR:

```yaml
# manifests/opa-policies/constraints/allowed-repos.yaml
parameters:
  repos:
    # ... other allowed registries ...
    - "ACCOUNT_ID.dkr.ecr."  # Allows all ECR repos in your account
```

**Important**: The `ACCOUNT_ID` placeholder is replaced during deployment via CI/CD:

```bash
# In your CI/CD pipeline
sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" \
  manifests/opa-policies/constraints/allowed-repos.yaml
kubectl apply -f manifests/opa-policies/constraints/allowed-repos.yaml
```

## Image Lifecycle Management

### Lifecycle Policies

Both repositories have automatic lifecycle policies:

**Infrastructure Repository**:
- Untagged images: Deleted after 7 days
- Tagged images: Keep last 20 versions (by tag prefixes: v*, prod*, staging*, dev*)

**Deployments Repository**:
- Untagged images: Deleted after 3 days
- Tagged images: Keep last 10 versions

### Viewing Lifecycle Policy

```bash
aws ecr get-lifecycle-policy \
  --repository-name infrastructure \
  --region $AWS_REGION
```

### Manual Cleanup

```bash
# List all images in a repository
aws ecr list-images \
  --repository-name infrastructure \
  --region $AWS_REGION

# Delete specific image
aws ecr batch-delete-image \
  --repository-name infrastructure \
  --image-ids imageTag=old-tag \
  --region $AWS_REGION
```

## Vulnerability Scanning

Images are automatically scanned on push. View scan results:

```bash
# Get scan findings
aws ecr describe-image-scan-findings \
  --repository-name infrastructure \
  --image-id imageTag=litellm-v1.80.5 \
  --region $AWS_REGION

# Example output
{
  "imageScanFindings": {
    "findingSeverityCounts": {
      "CRITICAL": 0,
      "HIGH": 2,
      "MEDIUM": 5,
      "LOW": 10
    }
  }
}
```

## Monitoring and Logging

### CloudWatch Metrics

ECR automatically publishes metrics to CloudWatch:

- `RepositoryPullCount` - Number of pulls
- `RepositoryPushCount` - Number of pushes

### View Metrics

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECR \
  --metric-name RepositoryPullCount \
  --dimensions Name=RepositoryName,Value=infrastructure \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --region $AWS_REGION
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build and push
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/deployments:myapp-$IMAGE_TAG .
          docker push $ECR_REGISTRY/deployments:myapp-$IMAGE_TAG
```

### GitLab CI Example

```yaml
build:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  before_script:
    - apk add --no-cache aws-cli
    - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
  script:
    - docker build -t $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/deployments:myapp-$CI_COMMIT_SHA .
    - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/deployments:myapp-$CI_COMMIT_SHA
```

## Troubleshooting

### Authentication Errors

```bash
# Error: "no basic auth credentials"
# Solution: Re-authenticate to ECR (tokens expire after 12 hours)
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

### Permission Denied

```bash
# Error: "denied: User: arn:aws:sts::xxx:assumed-role/xxx is not authorized"
# Solution: Attach the ECR push/pull policy to your IAM role
aws iam attach-role-policy \
  --role-name your-role \
  --policy-arn $(terraform output -raw ecr_push_pull_policy_arn)
```

### Tag Immutability Error

```bash
# Error: "The image tag 'xxx' already exists in the repository and cannot be overwritten"
# Solution: Infrastructure repo uses IMMUTABLE tags. Use a new tag version.
docker tag myimage:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/infrastructure:myimage-v1.0.1
```

### Image Pull Failures in Kubernetes

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. Wrong repository name or tag
# 2. Node doesn't have ECR permissions (should have AmazonEC2ContainerRegistryReadOnly)
# 3. Image doesn't exist in ECR

# Verify image exists
aws ecr describe-images \
  --repository-name infrastructure \
  --region $AWS_REGION
```

## Cost Optimization

### Storage Costs

- First 500 GB/month: Free
- After 500 GB: $0.10 per GB-month

### Data Transfer

- Pull from ECR to EC2/EKS in same region: Free
- Pull from ECR to internet: Standard data transfer rates

### Recommendations

1. Use lifecycle policies to clean up old images
2. Don't store large base images if they're publicly available
3. Use multi-stage builds to reduce image size
4. Enable image compression

## Security Best Practices

1. **Use Immutable Tags for Production**: Infrastructure repository enforces this
2. **Enable Vulnerability Scanning**: Enabled by default on push
3. **Encrypt Images**: KMS encryption enabled by default
4. **Principle of Least Privilege**: Use separate IAM policies for read vs. push/pull
5. **Monitor Access**: Review CloudWatch logs for unauthorized access attempts
6. **Regular Scans**: Review vulnerability scan results regularly
7. **Tag Strategy**: Use semantic versioning (v1.0.0) for production images

## Additional Resources

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [ECR Best Practices](https://docs.aws.amazon.com/AmazonECR/latest/userguide/best-practices.html)
- [ECR Image Scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [ECR Lifecycle Policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
