# Environment-Specific Configurations

This directory contains environment-specific Terraform variable files for managing multiple deployments (dev, staging, production).

## Usage

### Option 1: Separate tfvars files (Recommended)

Create environment-specific `.tfvars` files:

```bash
# Development
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"

# Staging
terraform plan -var-file="environments/staging.tfvars"
terraform apply -var-file="environments/staging.tfvars"

# Production
terraform plan -var-file="environments/prod.tfvars"
terraform apply -var-file="environments/prod.tfvars"
```

### Option 2: Terraform Workspaces

Alternatively, use Terraform workspaces:

```bash
# Create and switch to dev workspace
terraform workspace new dev
terraform workspace select dev
terraform apply -var-file="environments/dev.tfvars"

# Switch to prod workspace
terraform workspace select prod
terraform apply -var-file="environments/prod.tfvars"
```

## Environment Files

- `dev.tfvars` - Development environment (cost-optimized)
- `staging.tfvars` - Staging environment (production-like)
- `prod.tfvars` - Production environment (highly available)

## State Management

Each environment should use a **separate state file**:

### Using S3 Backend with Workspaces

Configure in `main.tf`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "litellm/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-locks"
  # Workspace will automatically append to the key path
}
```

Workspaces will store state at:
- `litellm/env:/dev/terraform.tfstate`
- `litellm/env:/staging/terraform.tfstate`
- `litellm/env:/prod/terraform.tfstate`

### Using S3 Backend with Separate Keys

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "litellm/${var.environment}/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-locks"
}
```

Then specify the key per environment:

```bash
terraform init -backend-config="key=litellm/dev/terraform.tfstate"
terraform init -backend-config="key=litellm/prod/terraform.tfstate"
```

## Best Practices

1. **Never share state files** between environments
2. **Use separate AWS accounts** for prod vs non-prod (recommended)
3. **Review plans carefully** before applying to production
4. **Test changes in dev** before promoting to staging/prod
5. **Use version control** for all `.tfvars` files (exclude secrets)
6. **Document environment differences** in comments within tfvars files
