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
# Main
# ============================================================================
main() {
    log "Starting LiteLLM infrastructure deployment..."
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    log "EKS Cluster: $EKS_CLUSTER_NAME"

    check_prerequisites

    case "${1:-all}" in
        validate)
            validate_yaml_files
            ;;
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
        dashboards)
            deploy_grafana_dashboards
            ;;
        jaeger)
            deploy_jaeger
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
        gatekeeper)
            deploy_gatekeeper
            ;;
        opa-policies)
            apply_opa_policies
            ;;
        opa-verify)
            verify_opa_policies
            ;;
        verify)
            verify_deployment
            ;;
        all)
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
        *)
            echo "Usage: $0 {validate|all|irsa|secrets|helm-repos|namespaces|external-secrets|monitoring|dashboards|jaeger|redis|litellm|openwebui|gatekeeper|opa-policies|opa-verify|verify}"
            exit 1
            ;;
    esac

    log "Deployment completed successfully!"
}

main "$@"
