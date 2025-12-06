# Terraform Infrastructure Changes

## 2025-12-05 - Infrastructure Review and Improvements

### Added

#### Environment Configurations
- **`environments/README.md`**: Comprehensive guide for managing multiple environments (dev/staging/prod)
- **`environments/dev.tfvars`**: Cost-optimized development environment configuration
  - 2 AZs, single NAT gateway, spot instances, smaller RDS
  - Estimated cost: ~$207/month
- **`environments/prod.tfvars`**: Production-ready configuration
  - 3 AZs, high availability, on-demand instances, Multi-AZ RDS
  - Estimated cost: ~$1,403/month

#### Backend Configuration
- **`backend.tf.example`**: Comprehensive S3 backend configuration examples
  - Single environment setup
  - Multi-environment with workspaces
  - Multi-environment with separate state files
  - Complete AWS setup commands
  - Migration guide from local state
  - Best practices documentation

#### Dependency Management
- **`renovate.json`**: Automated dependency updates for:
  - Terraform providers (AWS, Kubernetes, TLS, Random)
  - Terraform modules
  - Docker images
  - Helm charts
  - GitHub Actions
  - Security patch auto-merge with tests
  - Scheduled weekly updates (Mondays before 6am)
  - Native Terraform version detection (no custom regex managers needed)

### Enhanced

#### Documentation (`terraform/README.md`)

**Database Connection Setup**
- Added detailed section on AWS-managed RDS passwords
- External Secrets configuration examples for merging database credentials
- Two approaches documented with full YAML examples
- Commands to retrieve necessary ARNs from Terraform outputs

**Storage Class Configuration**
- New section 4.5 explaining GP3 vs GP2 storage class default handling
- Step-by-step commands to patch existing default storage class
- Explanation of when this step is needed

**VPC Subnet Configuration**
- Comprehensive subnet layout table showing CIDR allocation
- IP address planning guide
- Configurable subnet sizing examples
- Considerations for EKS pod IP requirements
- Recommendations for different workload sizes

#### VPC Module (`modules/vpc/`)

**New Variables** (`variables.tf`)
- `public_subnet_newbits`: Configurable public subnet sizing (default: 4 → /20)
- `private_subnet_newbits`: Configurable private subnet sizing (default: 4 → /20)
- `database_subnet_newbits`: Configurable database subnet sizing (default: 4 → /20)

**Updated Resources** (`main.tf`)
- Public subnets: Now use `var.public_subnet_newbits` with documentation
- Private subnets: Now use `var.private_subnet_newbits` with documentation
- Database subnets: Now use `var.database_subnet_newbits` with documentation
- Added comments explaining default IP allocation per subnet type

### Fixed

#### Security Improvements

**VPC Flow Logs IAM Policy** (`modules/vpc/main.tf:248-275`)
- Changed from wildcard `Resource = "*"` to specific log group ARN
- Split permissions into two statements:
  - Log operations scoped to specific log group
  - DescribeLogGroups limited to log group namespace only
- Follows AWS least-privilege best practices

#### EKS Module

**Node Group Lifecycle** (`modules/eks/main.tf:294-301`)
- Added `version` to `ignore_changes` lifecycle block
- Allows Kubernetes version upgrades outside of Terraform
- Prevents unintended downgrades or state drift
- Added explanatory comments
