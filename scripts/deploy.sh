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

check_prerequisites() {
    log "Checking prerequisites..."

    for cmd in aws kubectl helm eksctl; do
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
        error "kubectl not connected to cluster. Run: aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION"
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
    if ! aws iam get-role --role-name litellm-bedrock-role &> /dev/null; then
        aws iam create-role \
            --role-name litellm-bedrock-role \
            --assume-role-policy-document file:///tmp/litellm-trust-policy.json \
            --description "IAM role for LiteLLM to access Bedrock"

        aws iam put-role-policy \
            --role-name litellm-bedrock-role \
            --policy-name bedrock-invoke \
            --policy-document file://"$BASE_DIR/iam/litellm-bedrock-policy.json"

        log "Created litellm-bedrock-role"
    else
        log "litellm-bedrock-role already exists"
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

    if ! aws iam get-role --role-name external-secrets-role &> /dev/null; then
        aws iam create-role \
            --role-name external-secrets-role \
            --assume-role-policy-document file:///tmp/eso-trust-policy.json \
            --description "IAM role for External Secrets Operator"

        aws iam put-role-policy \
            --role-name external-secrets-role \
            --policy-name secrets-manager-read \
            --policy-document file://"$BASE_DIR/iam/external-secrets-policy.json"

        log "Created external-secrets-role"
    else
        log "external-secrets-role already exists"
    fi

    log "IRSA roles created successfully"
}

# ============================================================================
# Step 2: Create Secrets in AWS Secrets Manager
# ============================================================================
create_aws_secrets() {
    log "Creating secrets in AWS Secrets Manager..."

    # Generate master key if not exists
    if ! aws secretsmanager describe-secret --secret-id litellm/master-key --region "$AWS_REGION" &> /dev/null; then
        MASTER_KEY="sk-$(openssl rand -hex 32)"
        aws secretsmanager create-secret \
            --name litellm/master-key \
            --secret-string "$MASTER_KEY" \
            --region "$AWS_REGION"
        log "Created litellm/master-key secret"
        log "IMPORTANT: Retrieve your master key with: aws secretsmanager get-secret-value --secret-id litellm/master-key --region $AWS_REGION --query SecretString --output text"
    else
        log "litellm/master-key already exists"
    fi

    # Generate Redis password if not exists
    if ! aws secretsmanager describe-secret --secret-id litellm/redis-password --region "$AWS_REGION" &> /dev/null; then
        REDIS_PASSWORD="$(openssl rand -hex 16)"
        aws secretsmanager create-secret \
            --name litellm/redis-password \
            --secret-string "$REDIS_PASSWORD" \
            --region "$AWS_REGION"
        log "Created litellm/redis-password secret"
    else
        log "litellm/redis-password already exists"
    fi

    # Generate salt key if not exists (IMPORTANT: cannot be changed after deployment)
    if ! aws secretsmanager describe-secret --secret-id litellm/salt-key --region "$AWS_REGION" &> /dev/null; then
        SALT_KEY="$(openssl rand -hex 32)"
        aws secretsmanager create-secret \
            --name litellm/salt-key \
            --secret-string "$SALT_KEY" \
            --region "$AWS_REGION"
        log "Created litellm/salt-key secret"
    else
        log "litellm/salt-key already exists"
    fi

    # Check for database URL
    if ! aws secretsmanager describe-secret --secret-id litellm/database-url --region "$AWS_REGION" &> /dev/null; then
        log "WARNING: litellm/database-url secret does not exist!"
        log "Please create it with your RDS PostgreSQL connection string:"
        log "  aws secretsmanager create-secret --name litellm/database-url --secret-string 'postgresql://user:pass@host:5432/litellm' --region $AWS_REGION"
    else
        log "litellm/database-url exists"
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

    helm repo update

    log "Helm repositories added and updated"
}

# ============================================================================
# Step 4: Create Namespaces
# ============================================================================
create_namespaces() {
    log "Creating namespaces..."
    kubectl apply -f "$BASE_DIR/manifests/namespaces.yaml"
    log "Namespaces created"
}

# ============================================================================
# Step 5: Deploy External Secrets Operator
# ============================================================================
deploy_external_secrets() {
    log "Deploying External Secrets Operator..."

    # Create temp values file with correct account ID (don't modify original)
    sed "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" "$BASE_DIR/helm-values/external-secrets-values.yaml" > /tmp/external-secrets-values.yaml

    helm upgrade --install external-secrets external-secrets/external-secrets \
        -n external-secrets \
        -f /tmp/external-secrets-values.yaml \
        --wait --timeout 5m

    # Wait for webhook to be ready
    kubectl rollout status deployment/external-secrets-webhook -n external-secrets --timeout=120s

    log "External Secrets Operator deployed"
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

    helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
        -n monitoring \
        -f "$BASE_DIR/helm-values/kube-prometheus-stack-values.yaml" \
        --wait --timeout 10m

    log "kube-prometheus-stack deployed"
}

# ============================================================================
# Step 8: Deploy Redis HA (using DandyDeveloper chart with official Redis image)
# ============================================================================
deploy_redis() {
    log "Deploying Redis HA..."

    helm upgrade --install redis dandydev/redis-ha \
        -n litellm \
        -f "$BASE_DIR/helm-values/redis-values.yaml" \
        --wait --timeout 5m

    log "Redis HA deployed"
}

# ============================================================================
# Step 9: Deploy LiteLLM
# ============================================================================
deploy_litellm() {
    log "Deploying LiteLLM..."

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

    log "LiteLLM deployed"
}

# ============================================================================
# Step 10: Deploy OpenWebUI
# ============================================================================
deploy_openwebui() {
    log "Deploying OpenWebUI..."

    helm upgrade --install open-webui open-webui/open-webui \
        -n open-webui \
        -f "$BASE_DIR/helm-values/openwebui-values.yaml" \
        --wait --timeout 5m

    log "OpenWebUI deployed"
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
    kubectl get pods -A | grep -E 'litellm|open-webui|prometheus|redis|external-secrets|monitoring'

    echo ""
    echo "============================================"
    echo "Services:"
    echo "============================================"
    kubectl get svc -A | grep -E 'litellm|open-webui|prometheus|grafana|redis'

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

    log "Deployment verification complete"
}

# ============================================================================
# Main
# ============================================================================
main() {
    log "Starting LiteLLM infrastructure deployment..."
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    log "EKS Cluster: $EKS_CLUSTER_NAME"

    check_prerequisites

    case "${1:-all}" in
        irsa)
            create_irsa_roles
            ;;
        secrets)
            create_aws_secrets
            ;;
        helm-repos)
            add_helm_repos
            ;;
        namespaces)
            create_namespaces
            ;;
        external-secrets)
            deploy_external_secrets
            create_secret_stores
            ;;
        monitoring)
            deploy_monitoring
            ;;
        redis)
            deploy_redis
            ;;
        litellm)
            deploy_litellm
            ;;
        openwebui)
            deploy_openwebui
            ;;
        verify)
            verify_deployment
            ;;
        all)
            create_irsa_roles
            create_aws_secrets
            add_helm_repos
            create_namespaces
            deploy_external_secrets
            create_secret_stores
            deploy_monitoring
            deploy_redis
            deploy_litellm
            deploy_openwebui
            verify_deployment
            ;;
        *)
            echo "Usage: $0 {all|irsa|secrets|helm-repos|namespaces|external-secrets|monitoring|redis|litellm|openwebui|verify}"
            exit 1
            ;;
    esac

    log "Deployment completed successfully!"
}

main "$@"
