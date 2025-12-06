#!/bin/bash
# EC2 Bastion Setup Script for LiteLLM Testing
# This script creates an EC2 instance in the EKS VPC for testing access

set -euo pipefail

# ============================================================================
# Configuration - MODIFY THESE VALUES
# ============================================================================
export AWS_REGION="${AWS_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-my-eks-cluster}"
export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
export BASTION_NAME="${BASTION_NAME:-llm-bastion}"

# ============================================================================
# Helper Functions
# ============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

# ============================================================================
# Interactive Mode Configuration
# ============================================================================
INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"
AUTO_SKIP_HEALTHY="${AUTO_SKIP_HEALTHY:-false}"

# ============================================================================
# Interactive Prompt Functions
# ============================================================================

# Check if terminal supports interactive prompts
is_interactive() {
    [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -t 0 ]] && [[ -t 1 ]]
}

# Main interactive prompt function
# Arguments: resource_type, resource_name, [additional_info]
# Returns: 0=skip, 1=proceed, 2=quit
prompt_for_action() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_info="${3:-}"

    # Non-interactive mode
    if ! is_interactive; then
        log "Non-interactive mode: Proceeding with $resource_name"
        return 1
    fi

    # Auto-skip mode enabled
    if [[ "$AUTO_SKIP_HEALTHY" == "true" ]]; then
        log "Auto-skip enabled: Skipping $resource_name"
        return 0
    fi

    echo ""
    warn "$resource_type '$resource_name' already exists"
    if [[ -n "$additional_info" ]]; then
        echo "    $additional_info"
    fi
    echo ""
    echo "What would you like to do?"
    echo "  [S] Skip - Keep existing resource (recommended)"
    echo "  [P] Proceed - Update or replace the resource"
    echo "  [V] View - Show resource details"
    echo "  [Q] Quit - Exit setup"
    echo ""

    while true; do
        read -p "Choose [S/p/v/q]: " -n 1 -r choice
        echo ""

        case "${choice,,}" in
            s|"")
                log "Skipping $resource_name"
                return 0
                ;;
            p)
                log "Proceeding with $resource_name"
                return 1
                ;;
            v)
                show_resource_details "$resource_type" "$resource_name"
                echo ""
                continue
                ;;
            q)
                log "Setup cancelled by user"
                return 2
                ;;
            *)
                echo "Invalid choice. Please choose S, P, V, or Q."
                continue
                ;;
        esac
    done
}

# Show resource details
# Arguments: resource_type, resource_name
show_resource_details() {
    local resource_type="$1"
    local resource_name="$2"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Resource Details: $resource_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    case "$resource_type" in
        iam-role)
            if aws iam get-role --role-name "$resource_name" &> /dev/null; then
                echo "Role Name: $resource_name"
                echo "Role ARN:"
                aws iam get-role --role-name "$resource_name" --query 'Role.Arn' --output text
                echo ""
                echo "Attached Policies:"
                aws iam list-attached-role-policies --role-name "$resource_name" --query 'AttachedPolicies[*].PolicyName' --output text
                echo ""
                echo "Inline Policies:"
                aws iam list-role-policies --role-name "$resource_name" --query 'PolicyNames' --output text
            fi
            ;;
        instance-profile)
            if aws iam get-instance-profile --instance-profile-name "$resource_name" &> /dev/null; then
                echo "Instance Profile: $resource_name"
                aws iam get-instance-profile --instance-profile-name "$resource_name"
            fi
            ;;
        ec2-instance)
            local instance_id="$resource_name"
            if aws ec2 describe-instances --instance-ids "$instance_id" --region "$AWS_REGION" &> /dev/null; then
                echo "Instance ID: $instance_id"
                echo ""
                aws ec2 describe-instances --instance-ids "$instance_id" --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].[InstanceType,State.Name,LaunchTime,PrivateIpAddress,PublicIpAddress]' \
                    --output table
                echo ""
                echo "Tags:"
                aws ec2 describe-instances --instance-ids "$instance_id" --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].Tags' --output table
            fi
            ;;
        *)
            echo "Resource type '$resource_type' details not implemented"
            ;;
    esac

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# Get EKS VPC and Subnet Information
# ============================================================================
get_eks_network_info() {
    log "Getting EKS cluster network information..."

    # Get VPC ID from EKS cluster
    EKS_VPC_ID=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" \
        --query "cluster.resourcesVpcConfig.vpcId" --output text)

    if [[ -z "$EKS_VPC_ID" || "$EKS_VPC_ID" == "None" ]]; then
        error "Could not find VPC for EKS cluster: $EKS_CLUSTER_NAME"
    fi

    log "EKS VPC ID: $EKS_VPC_ID"

    # Get a private subnet from the EKS VPC
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$EKS_VPC_ID" "Name=map-public-ip-on-launch,Values=false" \
        --query "Subnets[0].SubnetId" --output text --region "$AWS_REGION")

    if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
        # Try to get any subnet if no private subnet found
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$EKS_VPC_ID" \
            --query "Subnets[0].SubnetId" --output text --region "$AWS_REGION")
    fi

    log "Subnet ID: $SUBNET_ID"

    # Get security group from EKS nodes
    EKS_NODE_SG=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$EKS_VPC_ID" "Name=group-name,Values=*eks*node*" \
        --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION")

    if [[ -z "$EKS_NODE_SG" || "$EKS_NODE_SG" == "None" ]]; then
        # Create a new security group for the bastion
        log "Creating security group for bastion..."
        EKS_NODE_SG=$(aws ec2 create-security-group \
            --group-name "$BASTION_NAME-sg" \
            --description "Security group for LLM bastion host" \
            --vpc-id "$EKS_VPC_ID" \
            --query "GroupId" --output text --region "$AWS_REGION")
        # Note: Default SG allows all outbound traffic, no egress rule needed
    fi

    log "Security Group ID: $EKS_NODE_SG"
}

# ============================================================================
# Create SSM Instance Profile
# ============================================================================
create_ssm_instance_profile() {
    log "Creating SSM instance profile..."

    ROLE_NAME="$BASTION_NAME-ssm-role"
    PROFILE_NAME="$BASTION_NAME-profile"

    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        # Role exists - prompt user
        prompt_for_action "iam-role" "$ROLE_NAME" "Used for SSM access to bastion instance"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping IAM role: $ROLE_NAME (already exists)"
                ;;
            1)  # Proceed - update policies
                log "Updating IAM role policies: $ROLE_NAME"

                # Re-attach SSM managed policy (idempotent)
                aws iam attach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

                # Update EKS describe policy
                cat > /tmp/eks-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
EOF

                aws iam put-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name eks-describe \
                    --policy-document file:///tmp/eks-policy.json

                log "Updated IAM role: $ROLE_NAME"
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    else
        # Role doesn't exist - create it
        log "Creating IAM role: $ROLE_NAME"

        # Create trust policy
        cat > /tmp/ec2-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/ec2-trust-policy.json

        # Attach SSM managed policy
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

        # Attach EKS describe policy for kubectl
        cat > /tmp/eks-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
EOF

        aws iam put-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name eks-describe \
            --policy-document file:///tmp/eks-policy.json

        log "Created IAM role: $ROLE_NAME"
    fi

    # Check if instance profile exists
    if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" &> /dev/null; then
        log "Instance profile already exists: $PROFILE_NAME"
        # Verify role is attached (idempotent)
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$PROFILE_NAME" \
            --role-name "$ROLE_NAME" 2>/dev/null || log "Role already attached to instance profile"
    else
        log "Creating instance profile: $PROFILE_NAME"
        aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME"
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$PROFILE_NAME" \
            --role-name "$ROLE_NAME"

        log "Created instance profile: $PROFILE_NAME"
        # Wait for profile to propagate
        sleep 10
    fi

    INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile \
        --instance-profile-name "$PROFILE_NAME" \
        --query "InstanceProfile.Arn" --output text)

    log "Instance Profile ARN: $INSTANCE_PROFILE_ARN"
}

# ============================================================================
# Get Latest Amazon Linux 2023 AMI
# ============================================================================
get_latest_ami() {
    log "Getting latest Amazon Linux 2023 AMI..."

    AMI_ID=$(aws ssm get-parameters \
        --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
        --query "Parameters[0].Value" --output text --region "$AWS_REGION")

    if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
        error "Could not find Amazon Linux 2023 AMI"
    fi

    log "AMI ID: $AMI_ID"
}

# ============================================================================
# Create User Data Script
# ============================================================================
create_user_data() {
    cat > /tmp/bastion-user-data.sh << EOF
#!/bin/bash
set -e

# Install kubectl with checksum verification
KUBECTL_VERSION=\$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/\${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/\${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "\$(cat kubectl.sha256)  kubectl" | sha256sum --check
chmod +x kubectl
mv kubectl /usr/local/bin/
rm kubectl.sha256

# Install helm with checksum verification
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
# Helm's install script verifies checksums internally
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

# Configure kubectl for EKS
mkdir -p /home/ec2-user/.kube
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube

# Add kubectl aliases
cat >> /home/ec2-user/.bashrc << 'ALIASES'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kga='kubectl get all'
alias kgpa='kubectl get pods -A'
alias kpf='kubectl port-forward'

# LiteLLM shortcuts
alias llm-ui='kubectl port-forward svc/open-webui 8080:80 -n open-webui --address 0.0.0.0'
alias llm-grafana='kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring --address 0.0.0.0'
alias llm-prometheus='kubectl port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 -n monitoring --address 0.0.0.0'
ALIASES

echo "Bastion setup complete!"
EOF
}

# ============================================================================
# Launch EC2 Instance
# ============================================================================
launch_instance() {
    log "Launching EC2 bastion instance..."

    # Check if instance already exists
    EXISTING_INSTANCE=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$BASTION_NAME" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
        --query "Reservations[0].Instances[0].InstanceId" --output text --region "$AWS_REGION")

    if [[ -n "$EXISTING_INSTANCE" && "$EXISTING_INSTANCE" != "None" ]]; then
        # Instance exists - get its state
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "$EXISTING_INSTANCE" \
            --query "Reservations[0].Instances[0].State.Name" --output text --region "$AWS_REGION")

        echo ""
        warn "EC2 Instance '$BASTION_NAME' already exists"
        echo "    Instance ID: $EXISTING_INSTANCE"
        echo "    State: $INSTANCE_STATE"
        echo ""

        prompt_for_action "ec2-instance" "$EXISTING_INSTANCE" "State: $INSTANCE_STATE"
        local action=$?

        case $action in
            0)  # Skip
                log "Using existing bastion instance: $EXISTING_INSTANCE"
                INSTANCE_ID="$EXISTING_INSTANCE"

                # If stopped, ask if user wants to start it
                if [[ "$INSTANCE_STATE" == "stopped" ]]; then
                    echo ""
                    read -p "Instance is stopped. Start it now? [Y/n]: " -r start_choice
                    if [[ ! "$start_choice" =~ ^[Nn]$ ]]; then
                        log "Starting instance: $INSTANCE_ID"
                        aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                    fi
                fi
                ;;
            1)  # Proceed - terminate and recreate
                echo ""
                echo "⚠️  WARNING: This will TERMINATE the existing instance and create a new one!"
                echo "    Instance ID: $EXISTING_INSTANCE"
                echo "    Any data on this instance will be LOST."
                echo ""
                read -p "Are you absolutely sure you want to terminate and recreate? [y/N]: " -r confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    log "Terminating existing instance: $EXISTING_INSTANCE"
                    aws ec2 terminate-instances --instance-ids "$EXISTING_INSTANCE" --region "$AWS_REGION"

                    log "Waiting for instance termination..."
                    aws ec2 wait instance-terminated --instance-ids "$EXISTING_INSTANCE" --region "$AWS_REGION"

                    log "Creating new bastion instance..."
                    # Fall through to create new instance below
                else
                    log "Termination cancelled. Using existing instance: $EXISTING_INSTANCE"
                    INSTANCE_ID="$EXISTING_INSTANCE"
                    # Skip to wait section
                    if [[ "$INSTANCE_STATE" == "running" ]]; then
                        # Already done, return early
                        return 0
                    fi
                fi
                ;;
            2)  # Quit
                exit 0
                ;;
        esac

        # If we're keeping the existing instance, skip creation
        if [[ -n "$INSTANCE_ID" ]]; then
            # Continue to wait section below
            :
        else
            # Create new instance (user confirmed termination)
            create_user_data
            USER_DATA=$(base64 < /tmp/bastion-user-data.sh | tr -d '\n')

            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id "$AMI_ID" \
                --instance-type "$INSTANCE_TYPE" \
                --subnet-id "$SUBNET_ID" \
                --security-group-ids "$EKS_NODE_SG" \
                --iam-instance-profile "Name=$BASTION_NAME-profile" \
                --user-data "$USER_DATA" \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$BASTION_NAME},{Key=Purpose,Value=LLM-Testing}]" \
                --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled" \
                --query "Instances[0].InstanceId" --output text --region "$AWS_REGION")

            log "Launched new instance: $INSTANCE_ID"
        fi
    else
        # No existing instance - create new one
        log "Creating new bastion instance..."
        create_user_data
        USER_DATA=$(base64 < /tmp/bastion-user-data.sh | tr -d '\n')

        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type "$INSTANCE_TYPE" \
            --subnet-id "$SUBNET_ID" \
            --security-group-ids "$EKS_NODE_SG" \
            --iam-instance-profile "Name=$BASTION_NAME-profile" \
            --user-data "$USER_DATA" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$BASTION_NAME},{Key=Purpose,Value=LLM-Testing}]" \
            --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled" \
            --query "Instances[0].InstanceId" --output text --region "$AWS_REGION")

        log "Launched instance: $INSTANCE_ID"
    fi

    # Wait for instance to be running
    log "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

    # Wait for SSM agent to be ready
    log "Waiting for SSM agent to be ready (this may take 2-3 minutes)..."
    for i in {1..30}; do
        STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --query "InstanceInformationList[0].PingStatus" --output text --region "$AWS_REGION" 2>/dev/null || echo "Unknown")

        if [[ "$STATUS" == "Online" ]]; then
            log "SSM agent is online"
            break
        fi
        echo -n "."
        sleep 10
    done
    echo ""
}

# ============================================================================
# Add IAM Principal to EKS
# ============================================================================
configure_eks_access() {
    log "Configuring EKS access for bastion..."

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$BASTION_NAME-ssm-role"

    # Check if using access entries or aws-auth configmap
    AUTH_MODE=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" \
        --query "cluster.accessConfig.authenticationMode" --output text 2>/dev/null || echo "CONFIG_MAP")

    if [[ "$AUTH_MODE" == *"API"* ]]; then
        log "Using EKS access entries..."
        aws eks create-access-entry \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --principal-arn "$ROLE_ARN" \
            --region "$AWS_REGION" 2>/dev/null || log "Access entry may already exist"

        aws eks associate-access-policy \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --principal-arn "$ROLE_ARN" \
            --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
            --access-scope type=cluster \
            --region "$AWS_REGION" 2>/dev/null || log "Policy may already be associated"
    else
        log "Using aws-auth ConfigMap..."
        log "Please manually add the following to the aws-auth ConfigMap in kube-system namespace:"
        echo ""
        echo "mapRoles:"
        echo "  - rolearn: $ROLE_ARN"
        echo "    username: bastion"
        echo "    groups:"
        echo "      - system:masters"
        echo ""
        echo "Run: kubectl edit configmap aws-auth -n kube-system"
    fi
}

# ============================================================================
# Print Access Instructions
# ============================================================================
print_instructions() {
    echo ""
    echo "============================================"
    echo "Bastion Instance Created Successfully!"
    echo "============================================"
    echo ""
    echo "Instance ID: $INSTANCE_ID"
    echo ""
    echo "To connect via SSM Session Manager:"
    echo "  aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
    echo ""
    echo "Once connected, use these commands:"
    echo ""
    echo "  # Access OpenWebUI (then open http://localhost:8080):"
    echo "  llm-ui"
    echo ""
    echo "  # Access Grafana (then open http://localhost:3000):"
    echo "  llm-grafana"
    echo ""
    echo "  # Access Prometheus (then open http://localhost:9090):"
    echo "  llm-prometheus"
    echo ""
    echo "  # Check all pods:"
    echo "  kgpa"
    echo ""
    echo "============================================"
}

# ============================================================================
# Cleanup Function
# ============================================================================
cleanup() {
    log "Cleaning up bastion resources..."

    # Get instance ID
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$BASTION_NAME" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" --output text --region "$AWS_REGION")

    if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" ]]; then
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
        log "Terminated instance: $INSTANCE_ID"
    fi

    # Delete instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$BASTION_NAME-profile" \
        --role-name "$BASTION_NAME-ssm-role" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$BASTION_NAME-profile" 2>/dev/null || true

    # Delete role policies and role
    aws iam detach-role-policy \
        --role-name "$BASTION_NAME-ssm-role" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
    aws iam delete-role-policy \
        --role-name "$BASTION_NAME-ssm-role" \
        --policy-name eks-describe 2>/dev/null || true
    aws iam delete-role --role-name "$BASTION_NAME-ssm-role" 2>/dev/null || true

    log "Cleanup complete"
}

# ============================================================================
# Main
# ============================================================================
main() {
    case "${1:-create}" in
        create)
            log "Creating bastion instance..."
            get_eks_network_info
            create_ssm_instance_profile
            get_latest_ami
            launch_instance
            configure_eks_access
            print_instructions
            ;;
        cleanup|delete)
            cleanup
            ;;
        connect)
            INSTANCE_ID=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$BASTION_NAME" "Name=instance-state-name,Values=running" \
                --query "Reservations[0].Instances[0].InstanceId" --output text --region "$AWS_REGION")
            if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" ]]; then
                aws ssm start-session --target "$INSTANCE_ID" --region "$AWS_REGION"
            else
                error "No running bastion instance found"
            fi
            ;;
        *)
            echo "Usage: $0 {create|cleanup|connect}"
            exit 1
            ;;
    esac
}

main "$@"
