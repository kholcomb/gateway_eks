#!/bin/bash
# LiteLLM + OpenWebUI + Observability Stack Deployment Script
# This script deploys the complete AI/LLM infrastructure to EKS

set -euo pipefail

# ============================================================================
# Configuration - MODIFY THESE VALUES
# ============================================================================
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-my-eks-cluster}"
export OIDC_PROVIDER="${OIDC_PROVIDER:-}"  # Will be auto-detected if empty

# Directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

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
SKIP_ALL="${SKIP_ALL:-false}"
AUTO_SKIP_MODE=false  # Set by user choosing [A]uto option

# ============================================================================
# Interactive Prompt Functions
# ============================================================================

# Check if terminal supports interactive prompts
is_interactive() {
    [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -t 0 ]] && [[ -t 1 ]]
}

# Main interactive prompt function
# Arguments: resource_type, resource_name, [namespace]
# Returns: 0=skip, 1=proceed, 2=quit
prompt_for_action() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"

    # Non-interactive mode
    if ! is_interactive; then
        if [[ "$SKIP_ALL" == "true" ]]; then
            log "Non-interactive mode: Skipping $resource_name"
            return 0
        else
            log "Non-interactive mode: Proceeding with $resource_name"
            return 1
        fi
    fi

    # Auto-skip mode enabled
    if [[ "$AUTO_SKIP_MODE" == "true" ]] || [[ "$AUTO_SKIP_HEALTHY" == "true" ]]; then
        log "Auto-skip enabled: Skipping $resource_name"
        return 0
    fi

    echo ""
    warn "$resource_type '$resource_name' already exists"
    if [[ -n "$namespace" ]]; then
        echo "    Namespace: $namespace"
    fi
    echo ""
    echo "What would you like to do?"
    echo "  [S] Skip - Skip this step (recommended if resource is healthy)"
    echo "  [P] Proceed - Run deployment anyway (may update existing resource)"
    echo "  [V] View - Show resource details"
    echo "  [A] Auto - Auto-skip all remaining healthy resources"
    echo "  [Q] Quit - Exit deployment"
    echo ""

    while true; do
        read -p "Choose [S/p/v/a/q]: " -n 1 -r choice
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
                show_resource_details "$resource_type" "$resource_name" "$namespace"
                echo ""
                continue
                ;;
            a)
                log "Auto-skip mode enabled for remaining resources"
                AUTO_SKIP_MODE=true
                return 0
                ;;
            q)
                log "Deployment cancelled by user"
                return 2
                ;;
            *)
                echo "Invalid choice. Please choose S, P, V, A, or Q."
                continue
                ;;
        esac
    done
}

# Show resource details
# Arguments: resource_type, resource_name, [namespace]
show_resource_details() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"

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
        aws-secret)
            if aws secretsmanager describe-secret --secret-id "$resource_name" --region "$AWS_REGION" &> /dev/null; then
                echo "Secret Name: $resource_name"
                echo "Created:"
                aws secretsmanager describe-secret --secret-id "$resource_name" --region "$AWS_REGION" --query 'CreatedDate' --output text
                echo "Last Modified:"
                aws secretsmanager describe-secret --secret-id "$resource_name" --region "$AWS_REGION" --query 'LastChangedDate' --output text
                echo ""
                echo "WARNING: Secret value is not displayed for security reasons"
            fi
            ;;
        namespace)
            if kubectl get namespace "$resource_name" &> /dev/null; then
                echo "Namespace: $resource_name"
                echo "Status:"
                kubectl get namespace "$resource_name" -o wide
                echo ""
                echo "Resources in namespace:"
                kubectl get all -n "$resource_name" 2>/dev/null || echo "  (empty)"
            fi
            ;;
        helm)
            if helm status "$resource_name" -n "$namespace" &> /dev/null; then
                echo "Release: $resource_name"
                echo "Namespace: $namespace"
                echo ""
                helm status "$resource_name" -n "$namespace"
            fi
            ;;
        *)
            echo "Resource type '$resource_type' details not implemented"
            ;;
    esac

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# Resource Existence Check Functions
# ============================================================================

# Check if IAM role exists
# Returns: 0=exists, 1=missing
check_iam_role_exists() {
    local role_name="$1"
    aws iam get-role --role-name "$role_name" &> /dev/null
}

# Check if AWS Secrets Manager secret exists
# Returns: 0=exists, 1=missing
check_aws_secret_exists() {
    local secret_name="$1"
    aws secretsmanager describe-secret --secret-id "$secret_name" --region "$AWS_REGION" &> /dev/null
}

# Check if Kubernetes namespace exists
# Returns: 0=exists, 1=missing
check_namespace_exists() {
    local namespace="$1"
    kubectl get namespace "$namespace" &> /dev/null
}

# Check if Helm release exists and get its status
# Returns: 0=healthy (deployed), 1=missing, 2=unhealthy
check_helm_release_exists() {
    local release="$1"
    local namespace="$2"
    local is_critical="${3:-false}"

    if ! helm status "$release" -n "$namespace" &> /dev/null; then
        return 1  # Does not exist
    fi

    # Check if status is "deployed"
    local status
    status=$(helm status "$release" -n "$namespace" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ "$status" == "deployed" ]]; then
        return 0  # Healthy
    else
        if [[ "$is_critical" == "true" ]]; then
            warn "Critical release $release is in state '$status' (not deployed)"
            warn "Skipping is not allowed for unhealthy critical dependencies"
        else
            warn "Release $release is in state '$status' (not deployed)"
            warn "Recommend proceeding to fix the release"
        fi
        return 2  # Unhealthy
    fi
}

# Check if EKS cluster exists
# Returns: 0=exists, 1=missing
check_eks_cluster_exists() {
    local cluster_name="$1"
    aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" &> /dev/null
}

# Get list of existing namespaces from a provided list
# Arguments: namespace1 namespace2 ...
# Outputs: List of existing namespaces
get_existing_namespaces() {
    local namespaces=("$@")
    local existing=()

    for ns in "${namespaces[@]}"; do
        if check_namespace_exists "$ns"; then
            existing+=("$ns")
        fi
    done

    echo "${existing[@]}"
}

# ============================================================================
# Dependency Validation Functions
# ============================================================================
# Based on DEPENDENCY_GRAPH.md
#
# Validates that required dependencies exist before allowing skip/proceed operations.
# This prevents broken deployments due to missing dependencies.

check_deployment_dependencies() {
    local resource_type="$1"
    local action="$2"  # "skip" or "proceed"

    case "$resource_type" in
        external-secrets)
            if [[ "$action" == "skip" ]]; then
                # If skipping, verify it's already deployed and healthy
                if ! helm status external-secrets -n external-secrets &>/dev/null; then
                    error "Cannot skip external-secrets: Not yet deployed"
                fi

                local status
                status=$(helm status external-secrets -n external-secrets -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
                if [[ "$status" != "deployed" ]]; then
                    error "Cannot skip external-secrets: Status is '$status', not 'deployed'"
                fi
            fi
            ;;

        secret-stores)
            # Must have External Secrets Operator deployed and healthy
            if ! helm status external-secrets -n external-secrets &>/dev/null; then
                error "Cannot deploy secret-stores: External Secrets Operator not found. Run: ./deploy.sh external-secrets"
            fi

            local eso_status
            eso_status=$(helm status external-secrets -n external-secrets -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ "$eso_status" != "deployed" ]]; then
                error "Cannot deploy secret-stores: External Secrets Operator status is '$eso_status', not 'deployed'"
            fi

            # Must have AWS secrets created
            for secret in litellm/master-key litellm/salt-key litellm/redis-password; do
                if ! aws secretsmanager describe-secret --secret-id "$secret" --region "$AWS_REGION" &>/dev/null; then
                    error "Cannot deploy secret-stores: AWS secret '$secret' not found. Run: ./deploy.sh secrets"
                fi
            done
            ;;

        redis)
            # Must have litellm namespace
            if ! check_namespace_exists "litellm"; then
                error "Cannot deploy Redis: 'litellm' namespace not found. Run: ./deploy.sh namespaces"
            fi

            # Must have litellm-secrets synced (check if K8s secret exists)
            if ! kubectl get secret litellm-secrets -n litellm &>/dev/null; then
                error "Cannot deploy Redis: litellm-secrets not found in litellm namespace. Run: ./deploy.sh external-secrets"
            fi

            # Verify secret is actually synced (has data)
            local secret_keys
            secret_keys=$(kubectl get secret litellm-secrets -n litellm -o jsonpath='{.data}' 2>/dev/null)
            if [[ -z "$secret_keys" || "$secret_keys" == "{}" ]]; then
                error "Cannot deploy Redis: litellm-secrets exists but has no data (not synced yet)"
            fi
            ;;

        litellm)
            # Must have litellm namespace
            if ! check_namespace_exists "litellm"; then
                error "Cannot deploy LiteLLM: 'litellm' namespace not found. Run: ./deploy.sh namespaces"
            fi

            # Must have Redis deployed and healthy
            if ! helm status redis -n litellm &>/dev/null; then
                error "Cannot deploy LiteLLM: Redis not found. Run: ./deploy.sh redis"
            fi

            local redis_status
            redis_status=$(helm status redis -n litellm -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ "$redis_status" != "deployed" ]]; then
                error "Cannot deploy LiteLLM: Redis status is '$redis_status', not 'deployed'"
            fi

            # Check Redis StatefulSet exists and has ready replicas
            if ! kubectl get statefulset redis-redis-ha-server -n litellm &>/dev/null; then
                error "Cannot deploy LiteLLM: Redis StatefulSet 'redis-redis-ha-server' not found"
            fi

            # Must have litellm-secrets synced
            if ! kubectl get secret litellm-secrets -n litellm &>/dev/null; then
                error "Cannot deploy LiteLLM: litellm-secrets not synced. Run: ./deploy.sh external-secrets"
            fi

            # Must have database-url secret in AWS Secrets Manager
            if ! aws secretsmanager describe-secret --secret-id litellm/database-url --region "$AWS_REGION" &>/dev/null; then
                error "Cannot deploy LiteLLM: litellm/database-url secret not found in AWS Secrets Manager. Create with: aws secretsmanager create-secret --name litellm/database-url --secret-string 'postgresql://user:pass@host:5432/litellm' --region $AWS_REGION"
            fi

            # Must have litellm-bedrock-role
            if ! check_iam_role_exists "litellm-bedrock-role"; then
                error "Cannot deploy LiteLLM: litellm-bedrock-role not found. Run: ./deploy.sh irsa"
            fi
            ;;

        openwebui)
            # Must have open-webui namespace
            if ! check_namespace_exists "open-webui"; then
                error "Cannot deploy OpenWebUI: 'open-webui' namespace not found. Run: ./deploy.sh namespaces"
            fi

            # Must have LiteLLM deployed and healthy
            if ! helm status litellm -n litellm &>/dev/null; then
                error "Cannot deploy OpenWebUI: LiteLLM not found. Run: ./deploy.sh litellm"
            fi

            local litellm_status
            litellm_status=$(helm status litellm -n litellm -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ "$litellm_status" != "deployed" ]]; then
                error "Cannot deploy OpenWebUI: LiteLLM status is '$litellm_status', not 'deployed'"
            fi

            # Check LiteLLM pods are running
            local litellm_pods
            litellm_pods=$(kubectl get pods -l app.kubernetes.io/name=litellm -n litellm --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            if [[ "$litellm_pods" -eq 0 ]]; then
                warn "LiteLLM pods are not running yet. OpenWebUI deployment may fail or take longer to start"
            fi

            # Must have openwebui-secrets synced
            if ! kubectl get secret openwebui-secrets -n open-webui &>/dev/null; then
                error "Cannot deploy OpenWebUI: openwebui-secrets not synced. Run: ./deploy.sh external-secrets"
            fi
            ;;

        namespaces)
            # No dependencies - namespaces are foundational
            ;;

        irsa)
            # Check OIDC provider is accessible
            get_oidc_provider  # This will set OIDC_PROVIDER variable
            if [[ -z "$OIDC_PROVIDER" ]]; then
                error "Cannot create IRSA roles: OIDC provider not found for cluster $EKS_CLUSTER_NAME"
            fi
            ;;

        monitoring|jaeger)
            # Independent - monitoring stack has no hard dependencies
            # Just check namespace exists
            if ! check_namespace_exists "monitoring"; then
                error "Cannot deploy $resource_type: 'monitoring' namespace not found. Run: ./deploy.sh namespaces"
            fi
            ;;

        *)
            # Unknown resource type - skip validation
            ;;
    esac
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate YAML files for syntax and Kubernetes spec compliance
validate_yaml_files() {
    log "Validating YAML files..."
    local has_errors=false

    # Validate manifest files (kubectl dry-run for spec validation)
    for file in "$BASE_DIR"/manifests/*.yaml; do
        if [[ -f "$file" ]]; then
            log "Validating $file..."
            if ! kubectl apply --dry-run=client -f "$file" > /dev/null 2>&1; then
                error_msg=$(kubectl apply --dry-run=client -f "$file" 2>&1)
                warn "Validation failed for $file: $error_msg"
                has_errors=true
            fi
        fi
    done

    # Validate Helm values files (YAML syntax check via kubectl)
    for file in "$BASE_DIR"/helm-values/*.yaml; do
        if [[ -f "$file" ]]; then
            log "Validating YAML syntax: $file..."
            # Use kubectl to parse YAML - will fail on syntax errors
            if ! kubectl create configmap yaml-test --from-file=test="$file" --dry-run=client -o yaml > /dev/null 2>&1; then
                warn "YAML syntax error in $file"
                has_errors=true
            fi
        fi
    done

    if [[ "$has_errors" == "true" ]]; then
        error "YAML validation failed. Please fix the errors above."
    fi

    log "All YAML files validated successfully"
}

# Validate Helm chart values against chart schema
validate_helm_values() {
    local chart="$1"
    local values_file="$2"
    local release_name="$3"

    log "Validating Helm values for $release_name..."

    # Use helm template to validate values against chart
    if ! helm template "$release_name" "$chart" -f "$values_file" > /dev/null 2>&1; then
        error_msg=$(helm template "$release_name" "$chart" -f "$values_file" 2>&1)
        error "Helm validation failed for $release_name: $error_msg"
    fi
}

# Wait for deployment to be ready with timeout
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300s}"

    log "Waiting for deployment $deployment in namespace $namespace..."
    if ! kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="$timeout"; then
        error "Deployment $deployment failed to become ready within $timeout"
    fi
    log "Deployment $deployment is ready"
}

# Wait for statefulset to be ready with timeout
wait_for_statefulset() {
    local namespace="$1"
    local statefulset="$2"
    local timeout="${3:-300s}"

    log "Waiting for statefulset $statefulset in namespace $namespace..."
    if ! kubectl rollout status statefulset/"$statefulset" -n "$namespace" --timeout="$timeout"; then
        error "StatefulSet $statefulset failed to become ready within $timeout"
    fi
    log "StatefulSet $statefulset is ready"
}

# Wait for all pods in a namespace with a label selector to be ready
wait_for_pods() {
    local namespace="$1"
    local selector="$2"
    local timeout="${3:-300s}"

    log "Waiting for pods with selector '$selector' in namespace $namespace..."
    if ! kubectl wait --for=condition=Ready pods -l "$selector" -n "$namespace" --timeout="$timeout"; then
        warn "Some pods with selector '$selector' are not ready. Checking status..."
        kubectl get pods -l "$selector" -n "$namespace"
        error "Pods failed to become ready within $timeout"
    fi
    log "All pods with selector '$selector' are ready"
}

# Verify Helm release is deployed and healthy
verify_helm_release() {
    local release="$1"
    local namespace="$2"

    log "Verifying Helm release $release in namespace $namespace..."

    # Check release exists and is deployed
    if ! helm status "$release" -n "$namespace" > /dev/null 2>&1; then
        error "Helm release $release not found in namespace $namespace"
    fi

    local status
    status=$(helm status "$release" -n "$namespace" -o json | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ "$status" != "deployed" ]]; then
        error "Helm release $release is in state '$status', expected 'deployed'"
    fi

    log "Helm release $release is deployed successfully"
}

check_prerequisites() {
    log "Checking prerequisites..."

    for cmd in aws kubectl helm; do
        if ! command -v "$cmd" &> /dev/null; then
            error "$cmd is required but not installed"
        fi
    done

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi

    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        warn "kubectl not connected to cluster"

        # Offer to fix kubectl context interactively
        if is_interactive; then
            echo ""
            echo "kubectl is not connected to the EKS cluster."
            echo "Command to fix: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION"
            echo ""
            read -p "Would you like to update kubeconfig now? [Y/n]: " -r choice

            if [[ "$choice" =~ ^[Nn]$ ]]; then
                error "kubectl not connected. Please run: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION"
            else
                log "Updating kubeconfig..."
                if aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"; then
                    log "Kubeconfig updated successfully"

                    # Verify connection
                    if kubectl cluster-info &> /dev/null; then
                        log "kubectl connection verified"
                    else
                        error "kubectl still cannot connect to cluster. Please check your EKS cluster name and region"
                    fi
                else
                    error "Failed to update kubeconfig. Please check your EKS cluster name and region"
                fi
            fi
        else
            error "kubectl not connected to cluster. Run: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION"
        fi
    fi

    log "Prerequisites check passed"
}

get_oidc_provider() {
    if [[ -z "$OIDC_PROVIDER" ]]; then
        OIDC_PROVIDER=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" \
            --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
        log "Detected OIDC provider: $OIDC_PROVIDER"
    fi
}

# ============================================================================
# Step 1: Create IRSA Roles
# ============================================================================
create_irsa_roles() {
    log "Creating IRSA roles..."

    get_oidc_provider

    # Create LiteLLM Bedrock role
    log "Creating LiteLLM Bedrock IAM role..."

    # Generate trust policy
    cat > /tmp/litellm-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:litellm:litellm-sa"
        }
      }
    }
  ]
}
EOF

    # Create role if it doesn't exist
    if check_iam_role_exists "litellm-bedrock-role"; then
        # Role exists - prompt user
        prompt_for_action "iam-role" "litellm-bedrock-role"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping litellm-bedrock-role (already exists)"
                ;;
            1)  # Proceed - update policies
                log "Updating litellm-bedrock-role policies..."
                aws iam put-role-policy \
                    --role-name litellm-bedrock-role \
                    --policy-name bedrock-invoke \
                    --policy-document file://"$BASE_DIR/iam/litellm-bedrock-policy.json"
                log "Updated litellm-bedrock-role"
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    else
        # Role doesn't exist - create it
        log "Creating litellm-bedrock-role..."
        aws iam create-role \
            --role-name litellm-bedrock-role \
            --assume-role-policy-document file:///tmp/litellm-trust-policy.json \
            --description "IAM role for LiteLLM to access Bedrock"

        aws iam put-role-policy \
            --role-name litellm-bedrock-role \
            --policy-name bedrock-invoke \
            --policy-document file://"$BASE_DIR/iam/litellm-bedrock-policy.json"

        log "Created litellm-bedrock-role"
    fi

    # Create External Secrets role
    log "Creating External Secrets IAM role..."

    cat > /tmp/eso-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }
  ]
}
EOF

    if check_iam_role_exists "external-secrets-role"; then
        # Role exists - prompt user
        prompt_for_action "iam-role" "external-secrets-role"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping external-secrets-role (already exists)"
                ;;
            1)  # Proceed - update policies
                log "Updating external-secrets-role policies..."
                aws iam put-role-policy \
                    --role-name external-secrets-role \
                    --policy-name secrets-manager-read \
                    --policy-document file://"$BASE_DIR/iam/external-secrets-policy.json"
                log "Updated external-secrets-role"
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    else
        # Role doesn't exist - create it
        log "Creating external-secrets-role..."
        aws iam create-role \
            --role-name external-secrets-role \
            --assume-role-policy-document file:///tmp/eso-trust-policy.json \
            --description "IAM role for External Secrets Operator"

        aws iam put-role-policy \
            --role-name external-secrets-role \
            --policy-name secrets-manager-read \
            --policy-document file://"$BASE_DIR/iam/external-secrets-policy.json"

        log "Created external-secrets-role"
    fi

    log "IRSA roles created successfully"
}

# ============================================================================
# Step 2: Create Secrets in AWS Secrets Manager
# ============================================================================
create_aws_secrets() {
    log "Creating secrets in AWS Secrets Manager..."

    # ========================================
    # litellm/master-key (CRITICAL: Regeneration breaks all API keys)
    # ========================================
    if check_aws_secret_exists "litellm/master-key"; then
        # Secret exists - this is CRITICAL
        echo ""
        warn "AWS Secret 'litellm/master-key' already exists"
        echo ""
        echo "⚠️  CRITICAL WARNING ⚠️"
        echo "Regenerating the master-key will INVALIDATE ALL EXISTING API KEYS!"
        echo "All users will need to generate new API keys after this operation."
        echo "This should only be done if you are setting up a fresh deployment"
        echo "or explicitly want to revoke all existing API keys."
        echo ""

        prompt_for_action "aws-secret" "litellm/master-key"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping litellm/master-key (already exists)"
                ;;
            1)  # Proceed - double confirmation required
                echo ""
                warn "You chose to regenerate the master-key"
                read -p "Are you absolutely sure you want to regenerate? This will break all API keys! [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    log "Regenerating litellm/master-key..."
                    MASTER_KEY="sk-$(openssl rand -hex 32)"
                    aws secretsmanager update-secret \
                        --secret-id litellm/master-key \
                        --secret-string "$MASTER_KEY" \
                        --region "$AWS_REGION"
                    log "Regenerated litellm/master-key"
                    log "IMPORTANT: Retrieve your new master key with: aws secretsmanager get-secret-value --secret-id litellm/master-key --region $AWS_REGION --query SecretString --output text"
                else
                    log "Regeneration cancelled - keeping existing master-key"
                fi
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    else
        # Secret doesn't exist - create it
        log "Creating litellm/master-key..."
        MASTER_KEY="sk-$(openssl rand -hex 32)"
        aws secretsmanager create-secret \
            --name litellm/master-key \
            --secret-string "$MASTER_KEY" \
            --region "$AWS_REGION"
        log "Created litellm/master-key secret"
        log "IMPORTANT: Retrieve your master key with: aws secretsmanager get-secret-value --secret-id litellm/master-key --region $AWS_REGION --query SecretString --output text"
    fi

    # ========================================
    # litellm/salt-key (CRITICAL: CANNOT be changed after deployment)
    # ========================================
    if check_aws_secret_exists "litellm/salt-key"; then
        # Salt key exists - ABSOLUTELY CANNOT regenerate
        echo ""
        warn "AWS Secret 'litellm/salt-key' already exists"
        echo ""
        echo "🛑 CRITICAL: Salt key CANNOT be changed after initial deployment!"
        echo "Changing the salt key will corrupt all encrypted data in the database."
        echo "If you need to change the salt key, you must redeploy the entire system."
        echo ""
        echo "Skipping salt-key (no option to regenerate for safety)"
        log "Skipping litellm/salt-key (already exists, cannot be changed)"
    else
        # Salt key doesn't exist - create it
        log "Creating litellm/salt-key..."
        SALT_KEY="$(openssl rand -hex 32)"
        aws secretsmanager create-secret \
            --name litellm/salt-key \
            --secret-string "$SALT_KEY" \
            --region "$AWS_REGION"
        log "Created litellm/salt-key secret"
        log "IMPORTANT: This salt key cannot be changed after deployment!"
    fi

    # ========================================
    # litellm/redis-password (Safe to regenerate with Redis restart)
    # ========================================
    if check_aws_secret_exists "litellm/redis-password"; then
        prompt_for_action "aws-secret" "litellm/redis-password"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping litellm/redis-password (already exists)"
                ;;
            1)  # Proceed
                log "Regenerating litellm/redis-password..."
                echo "Note: You will need to restart Redis for the new password to take effect"
                REDIS_PASSWORD="$(openssl rand -hex 16)"
                aws secretsmanager update-secret \
                    --secret-id litellm/redis-password \
                    --secret-string "$REDIS_PASSWORD" \
                    --region "$AWS_REGION"
                log "Regenerated litellm/redis-password"
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    else
        # Redis password doesn't exist - create it
        log "Creating litellm/redis-password..."
        REDIS_PASSWORD="$(openssl rand -hex 16)"
        aws secretsmanager create-secret \
            --name litellm/redis-password \
            --secret-string "$REDIS_PASSWORD" \
            --region "$AWS_REGION"
        log "Created litellm/redis-password secret"
    fi

    # ========================================
    # litellm/database-url (Required dependency - must exist)
    # ========================================
    if ! check_aws_secret_exists "litellm/database-url"; then
        error "litellm/database-url secret does not exist! This is required for LiteLLM deployment. Create it with: aws secretsmanager create-secret --name litellm/database-url --secret-string 'postgresql://user:pass@host:5432/litellm' --region $AWS_REGION"
    else
        log "litellm/database-url exists"

        # Optionally prompt to update database URL
        if is_interactive; then
            echo ""
            warn "AWS Secret 'litellm/database-url' already exists"
            echo "Changing the database URL will point LiteLLM to a different database."
            echo ""

            prompt_for_action "aws-secret" "litellm/database-url"
            local action=$?

            case $action in
                0)  # Skip
                    log "Keeping existing litellm/database-url"
                    ;;
                1)  # Proceed
                    warn "To update the database URL, use:"
                    echo "  aws secretsmanager update-secret --secret-id litellm/database-url --secret-string 'postgresql://user:pass@newhost:5432/litellm' --region $AWS_REGION"
                    log "Database URL not modified (manual update required for safety)"
                    ;;
                2)  # Quit
                    exit 0
                    ;;
            esac
        fi
    fi

    log "Secrets creation completed"
}

# ============================================================================
# Step 3: Add Helm Repositories
# ============================================================================
add_helm_repos() {
    log "Adding Helm repositories..."

    helm repo add external-secrets https://charts.external-secrets.io || true
    helm repo add dandydev https://dandydeveloper.github.io/charts || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo add open-webui https://helm.openwebui.com/ || true
    helm repo add jaegertracing https://jaegertracing.github.io/helm-charts || true
    helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts || true

    helm repo update

    log "Helm repositories added and updated"
}

# ============================================================================
# Step 4: Create Namespaces
# ============================================================================
create_namespaces() {
    log "Creating namespaces..."

    # Check which namespaces already exist
    local required_namespaces=("litellm" "open-webui" "monitoring" "external-secrets")
    local existing_ns
    existing_ns=$(get_existing_namespaces "${required_namespaces[@]}")

    if [[ -n "$existing_ns" ]]; then
        local existing_count=$(echo "$existing_ns" | wc -w)
        local total_count=${#required_namespaces[@]}

        echo ""
        warn "Namespaces: $existing_count of $total_count already exist ($existing_ns)"
        echo "Note: kubectl apply is idempotent, but you can skip if namespaces are already configured"
        echo ""

        prompt_for_action "namespace" "namespaces (batch)"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping namespace creation (already exist)"
                return 0
                ;;
            1)  # Proceed
                log "Applying namespace manifest (idempotent operation)..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    fi

    kubectl apply -f "$BASE_DIR/manifests/namespaces.yaml"
    log "Namespaces created"
}

# ============================================================================
# Step 5: Deploy External Secrets Operator
# ============================================================================
deploy_external_secrets() {
    log "Deploying External Secrets Operator..."

    # Check if Helm release already exists
    check_helm_release_exists "external-secrets" "external-secrets" "true"  # Critical dependency
    local status=$?

    if [[ $status -eq 0 ]]; then
        # Healthy - offer to skip
        prompt_for_action "helm" "external-secrets" "external-secrets"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping External Secrets Operator deployment (already healthy)"
                verify_helm_release "external-secrets" "external-secrets"
                return 0
                ;;
            1)  # Proceed
                log "Proceeding with External Secrets Operator upgrade..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    elif [[ $status -eq 2 ]]; then
        # Unhealthy - recommend proceeding
        warn "External Secrets Operator is in unhealthy state. Proceeding with deployment to fix..."
    fi

    # Validate dependencies
    check_deployment_dependencies "external-secrets" "proceed"

    # Create temp values file with correct account ID (don't modify original)
    sed "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" "$BASE_DIR/helm-values/external-secrets-values.yaml" > /tmp/external-secrets-values.yaml

    helm upgrade --install external-secrets external-secrets/external-secrets \
        -n external-secrets \
        -f /tmp/external-secrets-values.yaml \
        --wait --timeout 5m

    # Verify Helm release
    verify_helm_release "external-secrets" "external-secrets"

    # Wait for all ESO components to be ready
    wait_for_deployment "external-secrets" "external-secrets" "120s"
    wait_for_deployment "external-secrets" "external-secrets-webhook" "120s"
    wait_for_deployment "external-secrets" "external-secrets-cert-controller" "120s"

    log "External Secrets Operator deployed and verified"
}

# ============================================================================
# Step 6: Create ClusterSecretStore and ExternalSecrets
# ============================================================================
create_secret_stores() {
    log "Creating ClusterSecretStore and ExternalSecrets..."

    # Create temp manifest with correct region (don't modify original)
    sed "s/us-east-1/$AWS_REGION/g" "$BASE_DIR/manifests/cluster-secret-store.yaml" > /tmp/cluster-secret-store.yaml

    # Apply ClusterSecretStore
    kubectl apply -f /tmp/cluster-secret-store.yaml

    # Wait for ClusterSecretStore to be ready
    log "Waiting for ClusterSecretStore to be ready..."
    if kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=60s; then
        log "ClusterSecretStore is ready"
    else
        log "WARNING: ClusterSecretStore not ready after 60s"
    fi

    # Apply ExternalSecrets
    kubectl apply -f "$BASE_DIR/manifests/litellm-external-secret.yaml"
    kubectl apply -f "$BASE_DIR/manifests/openwebui-external-secret.yaml"

    log "ClusterSecretStore and ExternalSecrets created"
    log "Waiting for secrets to sync..."

    # Wait for ExternalSecrets to sync
    if kubectl wait --for=condition=Ready externalsecret/litellm-secrets -n litellm --timeout=60s; then
        log "litellm-secrets synced successfully"
    else
        log "WARNING: litellm-secrets not yet synced. Check ExternalSecret status."
    fi

    if kubectl wait --for=condition=Ready externalsecret/openwebui-secrets -n open-webui --timeout=60s; then
        log "openwebui-secrets synced successfully"
    else
        log "WARNING: openwebui-secrets not yet synced. Check ExternalSecret status."
    fi
}

# ============================================================================
# Step 7: Deploy kube-prometheus-stack
# ============================================================================
deploy_monitoring() {
    log "Deploying kube-prometheus-stack..."

    # Check if Helm release already exists
    check_helm_release_exists "kube-prometheus" "monitoring" "false"
    local status=$?

    if [[ $status -eq 0 ]]; then
        # Healthy - offer to skip
        prompt_for_action "helm" "kube-prometheus" "monitoring"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping kube-prometheus-stack deployment (already healthy)"
                verify_helm_release "kube-prometheus" "monitoring"
                # Still deploy dashboards in case they're missing
                deploy_grafana_dashboards
                return 0
                ;;
            1)  # Proceed
                log "Proceeding with kube-prometheus-stack upgrade..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    elif [[ $status -eq 2 ]]; then
        # Unhealthy - recommend proceeding
        warn "kube-prometheus-stack is in unhealthy state. Proceeding with deployment to fix..."
    fi

    # Validate dependencies
    check_deployment_dependencies "monitoring" "proceed"

    helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
        -n monitoring \
        -f "$BASE_DIR/helm-values/kube-prometheus-stack-values.yaml" \
        --wait --timeout 10m

    # Verify Helm release
    verify_helm_release "kube-prometheus" "monitoring"

    # Verify key pods are ready using kubectl wait
    log "Verifying Prometheus stack components..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=180s
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=alertmanager -n monitoring --timeout=180s

    log "kube-prometheus-stack deployed and verified"

    # Deploy Grafana dashboards as ConfigMaps
    deploy_grafana_dashboards
}

# ============================================================================
# Step 7a: Deploy Grafana Dashboards
# ============================================================================
deploy_grafana_dashboards() {
    log "Deploying Grafana dashboards..."

    # Create ConfigMap from LiteLLM Prometheus dashboard
    if [[ -f "$BASE_DIR/grafana_dashboards/litellm-prometheus.json" ]]; then
        kubectl create configmap grafana-dashboard-litellm \
            --from-file=litellm-prometheus.json="$BASE_DIR/grafana_dashboards/litellm-prometheus.json" \
            -n monitoring \
            --dry-run=client -o yaml | \
            kubectl label --local -f - grafana_dashboard=1 -o yaml | \
            kubectl apply -f -
        log "LiteLLM Prometheus dashboard deployed"
    fi

    log "Grafana dashboards deployed"
}

# ============================================================================
# Step 7b: Deploy Jaeger for Distributed Tracing
# ============================================================================
deploy_jaeger() {
    log "Deploying Jaeger for distributed tracing..."

    # Check if Helm release already exists
    check_helm_release_exists "jaeger" "monitoring" "false"
    local status=$?

    if [[ $status -eq 0 ]]; then
        # Healthy - offer to skip
        prompt_for_action "helm" "jaeger" "monitoring"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping Jaeger deployment (already healthy)"
                verify_helm_release "jaeger" "monitoring"
                return 0
                ;;
            1)  # Proceed
                log "Proceeding with Jaeger upgrade..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    elif [[ $status -eq 2 ]]; then
        # Unhealthy - recommend proceeding
        warn "Jaeger is in unhealthy state. Proceeding with deployment to fix..."
    fi

    # Validate dependencies
    check_deployment_dependencies "jaeger" "proceed"

    helm upgrade --install jaeger jaegertracing/jaeger \
        -n monitoring \
        -f "$BASE_DIR/helm-values/jaeger-values.yaml" \
        --wait --timeout 5m

    # Verify Helm release
    verify_helm_release "jaeger" "monitoring"

    # Verify Jaeger pod is ready
    log "Verifying Jaeger components..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=jaeger -n monitoring --timeout=120s

    log "Jaeger deployed and verified"
}

# ============================================================================
# Step 8: Deploy Redis HA (using DandyDeveloper chart with official Redis image)
# ============================================================================
deploy_redis() {
    log "Deploying Redis HA..."

    # Check if Helm release already exists
    check_helm_release_exists "redis" "litellm" "true"  # Critical dependency for LiteLLM
    local status=$?

    if [[ $status -eq 0 ]]; then
        # Healthy - offer to skip
        prompt_for_action "helm" "redis" "litellm"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping Redis HA deployment (already healthy)"
                verify_helm_release "redis" "litellm"
                return 0
                ;;
            1)  # Proceed
                log "Proceeding with Redis HA upgrade..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    elif [[ $status -eq 2 ]]; then
        # Unhealthy - must fix (critical dependency)
        warn "Redis HA is in unhealthy state. Proceeding with deployment to fix..."
    fi

    # Validate dependencies
    check_deployment_dependencies "redis" "proceed"

    helm upgrade --install redis dandydev/redis-ha \
        -n litellm \
        -f "$BASE_DIR/helm-values/redis-values.yaml" \
        --wait --timeout 5m

    # Verify Helm release
    verify_helm_release "redis" "litellm"

    # Verify Redis pods are ready (StatefulSet)
    log "Verifying Redis HA components..."
    kubectl wait --for=condition=Ready pod -l app=redis-ha -n litellm --timeout=180s

    # Verify Redis Sentinel is responding
    log "Checking Redis Sentinel connectivity..."
    if kubectl exec -n litellm redis-redis-ha-server-0 -- redis-cli -p 26379 SENTINEL masters > /dev/null 2>&1; then
        log "Redis Sentinel is responding"
    else
        warn "Redis Sentinel check failed - may still be initializing"
    fi

    log "Redis HA deployed and verified"
}

# ============================================================================
# Step 9: Deploy LiteLLM
# ============================================================================
deploy_litellm() {
    log "Deploying LiteLLM..."

    # Check if Helm release already exists
    check_helm_release_exists "litellm" "litellm" "true"  # Critical dependency for OpenWebUI
    local status=$?

    if [[ $status -eq 0 ]]; then
        # Healthy - offer to skip
        prompt_for_action "helm" "litellm" "litellm"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping LiteLLM deployment (already healthy)"
                verify_helm_release "litellm" "litellm"
                return 0
                ;;
            1)  # Proceed
                log "Proceeding with LiteLLM upgrade..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    elif [[ $status -eq 2 ]]; then
        # Unhealthy - must fix (critical dependency)
        warn "LiteLLM is in unhealthy state. Proceeding with deployment to fix..."
    fi

    # Validate dependencies
    check_deployment_dependencies "litellm" "proceed"

    # Create temp values file with correct account ID (don't modify original)
    sed "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" "$BASE_DIR/helm-values/litellm-values.yaml" > /tmp/litellm-values.yaml

    # Pull and install the OCI chart
    helm pull oci://ghcr.io/berriai/litellm-helm --untar -d /tmp/

    helm upgrade --install litellm /tmp/litellm-helm \
        -n litellm \
        -f /tmp/litellm-values.yaml \
        --wait --timeout 5m

    # Clean up temp chart directory
    rm -rf /tmp/litellm-helm

    # Verify Helm release
    verify_helm_release "litellm" "litellm"

    # Verify LiteLLM pods are ready
    log "Verifying LiteLLM components..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=litellm -n litellm --timeout=180s

    # Verify LiteLLM health endpoint
    log "Checking LiteLLM health endpoint..."
    local pod_name
    pod_name=$(kubectl get pod -l app.kubernetes.io/name=litellm -n litellm -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n litellm "$pod_name" -- wget -q -O - http://localhost:4000/health/liveliness > /dev/null 2>&1; then
        log "LiteLLM health check passed"
    else
        warn "LiteLLM health check failed - service may still be initializing"
    fi

    log "LiteLLM deployed and verified"
}

# ============================================================================
# Step 10: Deploy OpenWebUI
# ============================================================================
deploy_openwebui() {
    log "Deploying OpenWebUI..."

    # Check if Helm release already exists
    check_helm_release_exists "open-webui" "open-webui" "false"
    local status=$?

    if [[ $status -eq 0 ]]; then
        # Healthy - offer to skip
        prompt_for_action "helm" "open-webui" "open-webui"
        local action=$?

        case $action in
            0)  # Skip
                log "Skipping OpenWebUI deployment (already healthy)"
                verify_helm_release "open-webui" "open-webui"
                return 0
                ;;
            1)  # Proceed
                log "Proceeding with OpenWebUI upgrade..."
                ;;
            2)  # Quit
                exit 0
                ;;
        esac
    elif [[ $status -eq 2 ]]; then
        # Unhealthy - recommend proceeding
        warn "OpenWebUI is in unhealthy state. Proceeding with deployment to fix..."
    fi

    # Validate dependencies
    check_deployment_dependencies "openwebui" "proceed"

    helm upgrade --install open-webui open-webui/open-webui \
        -n open-webui \
        -f "$BASE_DIR/helm-values/openwebui-values.yaml" \
        --wait --timeout 5m

    # Verify Helm release
    verify_helm_release "open-webui" "open-webui"

    # Verify OpenWebUI pod is ready
    log "Verifying OpenWebUI components..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=open-webui -n open-webui --timeout=180s

    log "OpenWebUI deployed and verified"
}

# ============================================================================
# Step 11: Deploy OPA Gatekeeper
# ============================================================================
deploy_gatekeeper() {
    log "Deploying OPA Gatekeeper..."

    helm upgrade --install gatekeeper gatekeeper/gatekeeper \
        -n gatekeeper-system \
        --create-namespace \
        -f "$BASE_DIR/helm-values/gatekeeper-values.yaml" \
        --wait --timeout 5m

    # Verify Helm release
    verify_helm_release "gatekeeper" "gatekeeper-system"

    # Wait for Gatekeeper components to be ready
    log "Verifying Gatekeeper components..."
    kubectl wait --for=condition=Ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=180s
    kubectl wait --for=condition=Ready pod -l control-plane=audit-controller -n gatekeeper-system --timeout=180s

    log "OPA Gatekeeper deployed and verified"
}

# ============================================================================
# Step 12: Apply OPA Policies (Constraint Templates and Constraints)
# ============================================================================
apply_opa_policies() {
    log "Applying OPA constraint templates..."

    # Apply constraint templates first
    kubectl apply -f "$BASE_DIR/manifests/opa-policies/templates/"

    # Wait for constraint templates to be established
    log "Waiting for constraint templates to be ready..."
    sleep 10  # Give time for CRDs to be registered

    # Verify constraint templates are created
    local template_count
    template_count=$(kubectl get constrainttemplates --no-headers 2>/dev/null | wc -l)
    log "Created $template_count constraint templates"

    log "Applying OPA constraints (in dryrun mode)..."

    # Apply constraints
    kubectl apply -f "$BASE_DIR/manifests/opa-policies/constraints/"

    # Verify constraints are created
    local constraint_count
    constraint_count=$(kubectl get constraints --no-headers 2>/dev/null | wc -l)
    log "Created $constraint_count constraints"

    log "OPA policies applied successfully"
    log "NOTE: All constraints are in 'dryrun' mode. Change enforcementAction to 'deny' to enforce."
}

# ============================================================================
# Verify OPA Policy Status
# ============================================================================
verify_opa_policies() {
    log "Verifying OPA policy status..."

    echo ""
    echo "============================================"
    echo "Constraint Templates:"
    echo "============================================"
    kubectl get constrainttemplates

    echo ""
    echo "============================================"
    echo "Constraints and Violations:"
    echo "============================================"
    kubectl get constraints

    echo ""
    echo "============================================"
    echo "Audit Violations (if any):"
    echo "============================================"
    kubectl get constraints -o json | jq -r '.items[] | select(.status.totalViolations > 0) | "\(.metadata.name): \(.status.totalViolations) violations"' 2>/dev/null || echo "No violations found"

    log "OPA policy verification complete"
}

# ============================================================================
# Verification
# ============================================================================
verify_deployment() {
    log "Verifying deployment..."

    echo ""
    echo "============================================"
    echo "Pod Status:"
    echo "============================================"
    kubectl get pods -A | grep -E 'litellm|open-webui|prometheus|redis|external-secrets|monitoring|jaeger|gatekeeper'

    echo ""
    echo "============================================"
    echo "Services:"
    echo "============================================"
    kubectl get svc -A | grep -E 'litellm|open-webui|prometheus|grafana|redis|jaeger'

    echo ""
    echo "============================================"
    echo "Access Instructions:"
    echo "============================================"
    echo "From your bastion EC2 instance, run these commands:"
    echo ""
    echo "# Access OpenWebUI:"
    echo "kubectl port-forward svc/open-webui 8080:80 -n open-webui --address 0.0.0.0"
    echo "# Then open http://localhost:8080 in your browser"
    echo ""
    echo "# Access Grafana:"
    echo "kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring --address 0.0.0.0"
    echo "# Then open http://localhost:3000 (default: admin / prom-operator)"
    echo ""
    echo "# Access Prometheus:"
    echo "kubectl port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 -n monitoring --address 0.0.0.0"
    echo "# Then open http://localhost:9090"
    echo ""
    echo "# Access Jaeger UI (Distributed Tracing):"
    echo "kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring --address 0.0.0.0"
    echo "# Then open http://localhost:16686"
    echo ""

    echo "============================================"
    echo "OPA Gatekeeper Status:"
    echo "============================================"
    echo "# View policy violations:"
    echo "kubectl get constraints"
    echo ""
    echo "# View detailed violations for a constraint:"
    echo "kubectl describe k8sallowedrepos allowed-image-repos"
    echo ""

    log "Deployment verification complete"
}

# ============================================================================
# Infrastructure Provisioning Functions
# ============================================================================

# Interactive infrastructure deployment
deploy_infrastructure_interactive() {
    log "Deploying infrastructure using Terraform..."
    deploy_infrastructure
}

# Verify infrastructure components exist
verify_infrastructure() {
    log "Verifying infrastructure components..."
    echo ""

    local has_issues=false

    # Check Terraform directory
    if [[ ! -d "$BASE_DIR/terraform" ]]; then
        warn "Terraform directory not found"
        has_issues=true
    fi

    # Check if EKS cluster exists
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "EKS Cluster:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if check_eks_cluster_exists "$EKS_CLUSTER_NAME"; then
        echo "✓ EKS Cluster '$EKS_CLUSTER_NAME' exists"

        # Get cluster details
        local cluster_status
        cluster_status=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.status" --output text 2>/dev/null || echo "UNKNOWN")
        echo "  Status: $cluster_status"

        local cluster_version
        cluster_version=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.version" --output text 2>/dev/null || echo "UNKNOWN")
        echo "  Version: $cluster_version"

        local cluster_endpoint
        cluster_endpoint=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.endpoint" --output text 2>/dev/null || echo "UNKNOWN")
        echo "  Endpoint: $cluster_endpoint"
    else
        echo "✗ EKS Cluster '$EKS_CLUSTER_NAME' not found"
        has_issues=true
    fi
    echo ""

    # Check VPC
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VPC:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if check_eks_cluster_exists "$EKS_CLUSTER_NAME"; then
        local vpc_id
        vpc_id=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null)
        if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
            echo "✓ VPC: $vpc_id"

            # Count subnets
            local subnet_count
            subnet_count=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$AWS_REGION" --query "Subnets | length(@)" --output text 2>/dev/null || echo "0")
            echo "  Subnets: $subnet_count"
        else
            echo "✗ VPC not found for cluster"
            has_issues=true
        fi
    else
        echo "✗ Cannot check VPC (cluster not found)"
    fi
    echo ""

    # Check OIDC Provider
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "OIDC Provider:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if check_eks_cluster_exists "$EKS_CLUSTER_NAME"; then
        local oidc_issuer
        oidc_issuer=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.identity.oidc.issuer" --output text 2>/dev/null)
        if [[ -n "$oidc_issuer" && "$oidc_issuer" != "None" ]]; then
            echo "✓ OIDC Provider: $oidc_issuer"
        else
            echo "✗ OIDC Provider not configured"
            has_issues=true
        fi
    else
        echo "✗ Cannot check OIDC (cluster not found)"
    fi
    echo ""

    # Check IAM Roles
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "IAM Roles (IRSA):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if check_iam_role_exists "litellm-bedrock-role"; then
        echo "✓ litellm-bedrock-role exists"
    else
        echo "✗ litellm-bedrock-role not found"
        has_issues=true
    fi

    if check_iam_role_exists "external-secrets-role"; then
        echo "✓ external-secrets-role exists"
    else
        echo "✗ external-secrets-role not found"
        has_issues=true
    fi
    echo ""

    # Check AWS Secrets
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AWS Secrets Manager:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local secrets=("litellm/master-key" "litellm/salt-key" "litellm/redis-password" "litellm/database-url")
    for secret in "${secrets[@]}"; do
        if check_aws_secret_exists "$secret"; then
            echo "✓ $secret exists"
        else
            echo "✗ $secret not found"
            has_issues=true
        fi
    done
    echo ""

    # Check RDS
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RDS Database:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Try to extract DB endpoint from database-url secret
    if check_aws_secret_exists "litellm/database-url"; then
        local db_url
        db_url=$(aws secretsmanager get-secret-value --secret-id "litellm/database-url" --region "$AWS_REGION" --query "SecretString" --output text 2>/dev/null || echo "")
        if [[ -n "$db_url" ]]; then
            # Extract host from connection string (postgresql://user:pass@host:port/db)
            local db_host
            db_host=$(echo "$db_url" | sed -n 's|.*@\([^:]*\):.*|\1|p')
            if [[ -n "$db_host" ]]; then
                echo "✓ Database endpoint configured: $db_host"
            else
                echo "⚠ Database URL exists but could not parse endpoint"
            fi
        fi
    else
        echo "✗ Database URL secret not found"
        has_issues=true
    fi
    echo ""

    # Check kubectl connection
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "kubectl Connection:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if kubectl cluster-info &> /dev/null; then
        echo "✓ kubectl connected to cluster"
        local current_context
        current_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
        echo "  Context: $current_context"
    else
        echo "✗ kubectl not connected to cluster"
        echo "  Run: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION"
        has_issues=true
    fi
    echo ""

    # Summary
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ "$has_issues" == "false" ]]; then
        echo "✓ All infrastructure components verified"
        echo ""
        log "Infrastructure verification complete - ready for application deployment"
        return 0
    else
        echo "✗ Some infrastructure components are missing"
        echo ""
        log "Infrastructure verification found issues"
        if is_interactive; then
            echo ""
            read -p "Would you like to deploy missing infrastructure now? [Y/n]: " -r choice
            if [[ ! "$choice" =~ ^[Nn]$ ]]; then
                deploy_infrastructure
            fi
        fi
        return 1
    fi
}

# List all available components
list_components() {
    cat << 'COMPONENTS'
Available Components:

INFRASTRUCTURE DEPLOYMENT (Terraform):

Terraform (Full Infrastructure)
  ├─ vpc                  VPC, subnets, NAT gateways, route tables
  ├─ eks                  EKS cluster, node groups, OIDC provider
  ├─ rds                  PostgreSQL database (Multi-AZ)
  ├─ secrets              AWS Secrets Manager secrets
  ├─ iam                  IAM roles for IRSA (Bedrock, External Secrets)
  └─ bastion              (Optional) EC2 bastion for testing

  Use: ./deploy.sh terraform

APPLICATION (Kubernetes):
  ├─ namespaces           Kubernetes namespaces
  ├─ irsa                 IAM roles for service accounts
  ├─ helm-repos           Helm repository configuration
  ├─ external-secrets     External Secrets Operator + ClusterSecretStore
  ├─ gatekeeper           OPA Gatekeeper policy engine
  ├─ opa-policies         OPA policy constraints
  ├─ monitoring           Prometheus + Grafana + AlertManager
  ├─ dashboards           Grafana dashboards for LiteLLM
  ├─ jaeger               Distributed tracing
  ├─ redis                Redis HA (required for LiteLLM)
  ├─ litellm              LiteLLM AI gateway (requires Redis)
  └─ openwebui            OpenWebUI frontend (requires LiteLLM)

DEPLOYMENT MODES:
  ├─ infrastructure       Deploy infrastructure using Terraform
  ├─ terraform            Deploy full infrastructure (Terraform)
  ├─ all                  Deploy all applications (Kubernetes)
  ├─ complete             Deploy infrastructure + applications
  └─ <component>          Deploy specific component

VERIFICATION:
  ├─ infrastructure-verify  Check infrastructure components
  ├─ verify                 Check application deployments
  └─ opa-verify             Check OPA policy status

Run './deploy.sh help' for detailed usage information.
COMPONENTS
}

# Deploy infrastructure using Terraform
deploy_infrastructure() {
    log "Deploying infrastructure using Terraform..."

    local terraform_dir="$BASE_DIR/terraform"

    # Check if terraform directory exists
    if [[ ! -d "$terraform_dir" ]]; then
        error "Terraform directory not found: $terraform_dir"
    fi

    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform >= 1.5.0"
    fi

    # Check terraform version
    local tf_version
    tf_version=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
    log "Terraform version: $tf_version"

    cd "$terraform_dir" || error "Failed to change to terraform directory"

    # Check if terraform.tfvars exists
    if [[ ! -f "terraform.tfvars" ]]; then
        warn "terraform.tfvars not found. Please create it from terraform.tfvars.example"
        echo ""
        echo "Run: cp terraform.tfvars.example terraform.tfvars"
        echo "Then edit terraform.tfvars with your values"
        echo ""

        if is_interactive; then
            read -p "Would you like to create terraform.tfvars from the example now? [Y/n]: " -r choice
            if [[ ! "$choice" =~ ^[Nn]$ ]]; then
                cp terraform.tfvars.example terraform.tfvars
                log "Created terraform.tfvars from example"
                warn "Please edit terraform.tfvars before proceeding"

                # Open in default editor if available
                if [[ -n "${EDITOR:-}" ]]; then
                    "$EDITOR" terraform.tfvars
                else
                    echo "Edit with: ${VISUAL:-vi} terraform.tfvars"
                fi

                read -p "Press Enter when ready to continue..."
            else
                error "terraform.tfvars is required for deployment"
            fi
        else
            error "terraform.tfvars is required. Create it from terraform.tfvars.example"
        fi
    fi

    # Initialize Terraform if needed
    if [[ ! -d ".terraform" ]]; then
        log "Initializing Terraform..."
        terraform init || error "Terraform init failed"
    fi

    # Validate Terraform configuration
    log "Validating Terraform configuration..."
    terraform validate || error "Terraform validation failed"

    # Plan
    log "Running Terraform plan..."
    terraform plan -out=tfplan || error "Terraform plan failed"

    # Confirm apply
    if is_interactive; then
        echo ""
        warn "Terraform plan complete. Review the plan above."
        echo ""
        read -p "Apply this plan? This will create AWS infrastructure. [y/N]: " -r confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "Terraform apply cancelled"
            rm -f tfplan
            cd "$BASE_DIR" || true
            exit 0
        fi
    fi

    # Apply
    log "Applying Terraform configuration..."
    terraform apply tfplan || error "Terraform apply failed"
    rm -f tfplan

    # Export variables for subsequent deployment
    log "Exporting Terraform outputs..."
    export AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "$AWS_REGION")
    export EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "$EKS_CLUSTER_NAME")
    export AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id 2>/dev/null || aws sts get-caller-identity --query Account --output text)

    log "Infrastructure deployment complete!"
    log ""
    log "Next steps:"
    log "1. Configure kubectl: $(terraform output -raw configure_kubectl)"
    log "2. Run application deployment: $BASE_DIR/scripts/deploy.sh all"

    cd "$BASE_DIR" || true
}

# Destroy infrastructure using Terraform
destroy_infrastructure() {
    log "Destroying infrastructure using Terraform..."

    local terraform_dir="$BASE_DIR/terraform"

    if [[ ! -d "$terraform_dir" ]]; then
        error "Terraform directory not found: $terraform_dir"
    fi

    cd "$terraform_dir" || error "Failed to change to terraform directory"

    # Confirm destruction
    echo ""
    warn "⚠️  WARNING: This will DESTROY all infrastructure resources!"
    echo "This includes:"
    echo "  - EKS cluster and all workloads"
    echo "  - RDS database (data will be lost unless you have backups)"
    echo "  - VPC and networking"
    echo "  - Secrets in AWS Secrets Manager"
    echo "  - Bastion instance (if created)"
    echo ""

    if is_interactive; then
        read -p "Type 'destroy' to confirm destruction: " -r confirm

        if [[ "$confirm" != "destroy" ]]; then
            log "Destruction cancelled"
            cd "$BASE_DIR" || true
            exit 0
        fi

        read -p "Are you absolutely sure? [y/N]: " -r confirm2
        if [[ ! "$confirm2" =~ ^[Yy]$ ]]; then
            log "Destruction cancelled"
            cd "$BASE_DIR" || true
            exit 0
        fi
    fi

    # Destroy
    log "Destroying infrastructure..."
    terraform destroy -auto-approve || error "Terraform destroy failed"

    log "Infrastructure destroyed successfully"
    cd "$BASE_DIR" || true
}

# Plan infrastructure changes using Terraform
plan_infrastructure() {
    log "Planning infrastructure changes..."

    local terraform_dir="$BASE_DIR/terraform"

    if [[ ! -d "$terraform_dir" ]]; then
        error "Terraform directory not found: $terraform_dir"
    fi

    cd "$terraform_dir" || error "Failed to change to terraform directory"

    # Initialize if needed
    if [[ ! -d ".terraform" ]]; then
        log "Initializing Terraform..."
        terraform init || error "Terraform init failed"
    fi

    # Validate
    log "Validating Terraform configuration..."
    terraform validate || error "Terraform validation failed"

    # Plan
    log "Running Terraform plan..."
    terraform plan || error "Terraform plan failed"

    cd "$BASE_DIR" || true
}

# ============================================================================
# Complete End-to-End Deployment
# ============================================================================
deploy_complete() {
    log "Starting complete end-to-end deployment..."
    log "This will:"
    log "  1. Deploy infrastructure (Terraform)"
    log "  2. Configure kubectl"
    log "  3. Deploy applications to Kubernetes"
    echo ""

    # Deploy infrastructure
    deploy_infrastructure

    # Configure kubectl
    log "Configuring kubectl..."
    local terraform_dir="$BASE_DIR/terraform"
    cd "$terraform_dir" || error "Failed to change to terraform directory"

    local kubectl_cmd
    kubectl_cmd=$(terraform output -raw configure_kubectl 2>/dev/null)

    if [[ -n "$kubectl_cmd" ]]; then
        eval "$kubectl_cmd" || error "Failed to configure kubectl"
        log "kubectl configured successfully"
    else
        warn "Could not get kubectl configuration from Terraform output"
        log "Attempting to configure kubectl manually..."
        aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" || error "Failed to configure kubectl"
    fi

    cd "$BASE_DIR" || true

    # Verify kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl cannot connect to cluster. Please check your configuration"
    fi

    # Deploy applications
    log "Deploying applications to Kubernetes..."
    validate_yaml_files
    create_irsa_roles
    create_aws_secrets
    add_helm_repos
    create_namespaces
    deploy_external_secrets
    create_secret_stores
    deploy_gatekeeper
    apply_opa_policies
    deploy_monitoring
    deploy_jaeger
    deploy_redis
    deploy_litellm
    deploy_openwebui
    verify_deployment
    verify_opa_policies

    log "Complete deployment finished successfully!"
}

# ============================================================================
# Main
# ============================================================================
main() {
    log "Starting LiteLLM infrastructure deployment..."
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    log "EKS Cluster: $EKS_CLUSTER_NAME"

    case "${1:-all}" in
        # Infrastructure provisioning commands
        infra|infrastructure)
            deploy_infrastructure_interactive
            ;;
        infra-terraform|infrastructure-terraform|terraform)
            deploy_infrastructure
            ;;
        infra-plan|infrastructure-plan)
            plan_infrastructure
            ;;
        infra-verify|infrastructure-verify|verify-infra)
            verify_infrastructure
            ;;
        infra-destroy|infrastructure-destroy|infrastructure-destroy-terraform)
            destroy_infrastructure
            ;;
        complete|full)
            deploy_complete
            ;;

        # Component listing
        list|components|ls)
            list_components
            ;;

        # Existing application deployment commands
        validate)
            check_prerequisites
            validate_yaml_files
            ;;
        irsa)
            check_prerequisites
            create_irsa_roles
            ;;
        secrets)
            check_prerequisites
            create_aws_secrets
            ;;
        helm-repos)
            check_prerequisites
            add_helm_repos
            ;;
        namespaces)
            check_prerequisites
            create_namespaces
            ;;
        external-secrets)
            check_prerequisites
            deploy_external_secrets
            create_secret_stores
            ;;
        monitoring)
            check_prerequisites
            deploy_monitoring
            ;;
        dashboards)
            check_prerequisites
            deploy_grafana_dashboards
            ;;
        jaeger)
            check_prerequisites
            deploy_jaeger
            ;;
        redis)
            check_prerequisites
            deploy_redis
            ;;
        litellm)
            check_prerequisites
            deploy_litellm
            ;;
        openwebui)
            check_prerequisites
            deploy_openwebui
            ;;
        gatekeeper)
            check_prerequisites
            deploy_gatekeeper
            ;;
        opa-policies)
            check_prerequisites
            apply_opa_policies
            ;;
        opa-verify)
            check_prerequisites
            verify_opa_policies
            ;;
        verify)
            check_prerequisites
            verify_deployment
            ;;
        all)
            check_prerequisites
            validate_yaml_files
            create_irsa_roles
            create_aws_secrets
            add_helm_repos
            create_namespaces
            deploy_external_secrets
            create_secret_stores
            deploy_gatekeeper
            apply_opa_policies
            deploy_monitoring
            deploy_jaeger
            deploy_redis
            deploy_litellm
            deploy_openwebui
            verify_deployment
            verify_opa_policies
            ;;
        help|--help|-h)
            cat << 'HELP'
LiteLLM Deployment Script

USAGE:
    ./deploy.sh [COMMAND]

INFRASTRUCTURE COMMANDS:
    infrastructure, infra             Deploy infrastructure using Terraform
    infrastructure-terraform, terraform Deploy using Terraform (VPC, EKS, RDS, Secrets Manager)
    infrastructure-plan, infra-plan   Show Terraform infrastructure changes
    infrastructure-verify, infra-verify Verify infrastructure components exist
    infrastructure-destroy            Destroy Terraform-managed infrastructure
    complete, full                    Deploy infrastructure + configure kubectl + deploy apps

APPLICATION DEPLOYMENT COMMANDS (Kubernetes):
    all                   Deploy all application components to existing EKS cluster
    list, components, ls  List all available components and deployment modes
    validate              Validate YAML files only
    irsa                  Create IAM roles for service accounts
    secrets               Create secrets in AWS Secrets Manager
    helm-repos            Add Helm repositories
    namespaces            Create Kubernetes namespaces
    external-secrets      Deploy External Secrets Operator and sync secrets
    monitoring            Deploy kube-prometheus-stack
    dashboards            Deploy Grafana dashboards
    jaeger                Deploy Jaeger for distributed tracing
    redis                 Deploy Redis HA
    litellm               Deploy LiteLLM application
    openwebui             Deploy OpenWebUI frontend
    gatekeeper            Deploy OPA Gatekeeper
    opa-policies          Apply OPA policies
    opa-verify            Verify OPA policy status
    verify                Verify deployment status

ENVIRONMENT VARIABLES:
    AWS_REGION            AWS region (default: us-east-1)
    AWS_ACCOUNT_ID        AWS account ID (auto-detected if not set)
    EKS_CLUSTER_NAME      EKS cluster name (default: my-eks-cluster)
    INTERACTIVE_MODE      Enable interactive prompts (default: true)
    AUTO_SKIP_HEALTHY     Auto-skip healthy resources (default: false)
    SKIP_ALL              Skip all prompts in non-interactive mode (default: false)

EXAMPLES:
    # Deploy infrastructure using Terraform
    ./deploy.sh infrastructure

    # Deploy using Terraform (full infrastructure with RDS)
    ./deploy.sh terraform

    # Complete deployment from scratch
    ./deploy.sh complete

    # Verify infrastructure exists
    ./deploy.sh infrastructure-verify

    # List all available components
    ./deploy.sh list

    # Preview Terraform infrastructure changes
    ./deploy.sh infrastructure-plan

    # Deploy applications to existing cluster
    ./deploy.sh all

    # Deploy specific components selectively
    ./deploy.sh redis
    ./deploy.sh litellm
    ./deploy.sh openwebui

    # Destroy infrastructure
    ./deploy.sh infrastructure-destroy

    # Non-interactive deployment
    INTERACTIVE_MODE=false ./deploy.sh all

    # Auto-skip healthy resources
    AUTO_SKIP_HEALTHY=true ./deploy.sh all

For more information, see scripts/README.md
HELP
            exit 0
            ;;
        *)
            echo "Usage: $0 {infrastructure|infrastructure-plan|infrastructure-destroy|complete|all|validate|...}"
            echo "Run '$0 help' for full usage information"
            exit 1
            ;;
    esac

    log "Deployment completed successfully!"
}

main "$@"
