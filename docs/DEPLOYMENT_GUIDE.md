# LiteLLM + OpenWebUI Deployment Guide

Complete step-by-step guide for deploying LiteLLM proxy with OpenWebUI on Amazon EKS.

**Prerequisites:** Ensure you've completed the [infrastructure deployment](../README.md#prerequisites) (eksctl or Terraform) and have kubectl configured.

---

## Infrastructure Options

**Deployment guides:**
- [eksctl deployment](../eksctl/README.md)
- [Terraform deployment](../terraform/README.md)

---

## Quick Start

### Step 1: Set Environment Variables

```bash
export AWS_REGION="us-east-1"
export EKS_CLUSTER_NAME="litellm-eks"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### Step 2: Create AWS Secrets

Before deploying applications, create all required secrets in AWS Secrets Manager.

#### LiteLLM Secrets

```bash
# JWT Public Key URL (Okta JWKS endpoint)
aws secretsmanager create-secret \
  --name litellm/jwt-public-key-url \
  --description "Okta JWKS endpoint for JWT validation" \
  --secret-string "https://<your-okta-domain>/oauth2/default/v1/keys" \
  --region $AWS_REGION

# Database URL (if not created by Terraform)
aws secretsmanager create-secret \
  --name litellm/database-url \
  --secret-string "postgresql://username:password@rds-endpoint:5432/litellm" \
  --region $AWS_REGION
```

**Note:** The deploy script auto-generates `master-key`, `salt-key`, and `redis-password` if they don't exist.

#### OpenWebUI Secrets

```bash
# Session encryption key
aws secretsmanager create-secret \
  --name openwebui/webui-secret-key \
  --description "OpenWebUI session encryption key" \
  --secret-string "$(openssl rand -hex 32)" \
  --region $AWS_REGION

# Okta OpenID configuration URL
aws secretsmanager create-secret \
  --name openwebui/okta-openid-url \
  --description "Okta OpenID Connect discovery URL" \
  --secret-string "https://<your-okta-domain>/oauth2/default/.well-known/openid-configuration" \
  --region $AWS_REGION

# Okta Client ID (from Okta application)
aws secretsmanager create-secret \
  --name openwebui/okta-client-id \
  --description "Okta OIDC Application Client ID" \
  --secret-string "<your-client-id>" \
  --region $AWS_REGION

# Okta Client Secret (from Okta application)
aws secretsmanager create-secret \
  --name openwebui/okta-client-secret \
  --description "Okta OIDC Application Client Secret" \
  --secret-string "<your-client-secret>" \
  --region $AWS_REGION

# Admin user emails (comma-separated)
aws secretsmanager create-secret \
  --name openwebui/admin-email \
  --description "Admin user email addresses" \
  --secret-string "admin@yourcompany.com" \
  --region $AWS_REGION
```

**Replace placeholders:**
- `<your-okta-domain>` - Your Okta domain (e.g., `dev-123456.okta.com`)
- `<your-client-id>` - Okta application Client ID
- `<your-client-secret>` - Okta application Client Secret

**See [JWT_AUTHENTICATION_SETUP.md](JWT_AUTHENTICATION_SETUP.md)** for complete Okta configuration.

#### Verify All Secrets

```bash
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `litellm/`) || starts_with(Name, `openwebui/`)].Name'
```

Expected output:
```json
[
    "litellm/database-url",
    "litellm/jwt-public-key-url",
    "litellm/master-key",
    "litellm/redis-password",
    "litellm/salt-key",
    "openwebui/admin-email",
    "openwebui/okta-client-id",
    "openwebui/okta-client-secret",
    "openwebui/okta-openid-url",
    "openwebui/webui-secret-key"
]
```

### Step 3: Deploy All Applications

```bash
cd scripts
./deploy.sh all
```

The deployment script will:
1. ✅ Validate YAML configurations
2. ✅ Create IRSA roles for Bedrock and External Secrets
3. ✅ Create auto-generated secrets (master-key, salt-key, redis-password)
4. ✅ Add Helm repositories
5. ✅ Create Kubernetes namespaces
6. ✅ Deploy External Secrets Operator
7. ✅ Create ClusterSecretStore and sync secrets
8. ✅ Deploy OPA Gatekeeper and policies
9. ✅ Deploy Prometheus/Grafana monitoring
10. ✅ Deploy Jaeger distributed tracing
11. ✅ Deploy Redis HA cluster
12. ✅ Deploy LiteLLM proxy with JWT authentication
13. ✅ Deploy OpenWebUI with Okta OIDC
14. ✅ Verify all components

### Step 4: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A | grep -E 'litellm|open-webui|monitoring|redis'

# Check External Secrets synced
kubectl get externalsecret -n litellm
kubectl get externalsecret -n open-webui

# Verify secrets were created
kubectl get secret litellm-secrets -n litellm
kubectl get secret openwebui-secrets -n open-webui
```

### Step 5: Access Applications

**Option A: Bastion Host (Recommended for Production)**

```bash
# Create and connect to bastion
./scripts/setup-bastion.sh create
./scripts/setup-bastion.sh connect

# Inside bastion, use aliases:
llm-ui          # Port-forward OpenWebUI to localhost:8080
llm-grafana     # Port-forward Grafana to localhost:3000
llm-prometheus  # Port-forward Prometheus to localhost:9090
llm-jaeger      # Port-forward Jaeger to localhost:16686
```

**Option B: Direct Port-Forward (Development)**

```bash
# OpenWebUI
kubectl port-forward -n open-webui svc/open-webui 8080:80 --address 0.0.0.0

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80 --address 0.0.0.0

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-kube-prome-prometheus 9090:9090 --address 0.0.0.0

# Jaeger
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686 --address 0.0.0.0
```

---

## Incremental Deployment

Deploy specific components individually:

```bash
# Infrastructure & IAM
./deploy.sh irsa                 # Create IAM roles (IRSA)
./deploy.sh secrets              # Create AWS secrets (LiteLLM only)

# Core services
./deploy.sh external-secrets     # Deploy External Secrets Operator
./deploy.sh gatekeeper           # Deploy OPA Gatekeeper
./deploy.sh opa-policies         # Apply OPA policies

# Data & caching
./deploy.sh redis                # Deploy Redis HA

# Applications
./deploy.sh litellm              # Deploy LiteLLM proxy
./deploy.sh openwebui            # Deploy OpenWebUI frontend

# Observability
./deploy.sh monitoring           # Deploy Prometheus/Grafana
./deploy.sh jaeger               # Deploy Jaeger tracing

# Verification
./deploy.sh verify               # Verify all components
```

---

## Deployment Modes

### Interactive Mode (Default)

The script prompts before deploying resources that already exist:

```bash
./deploy.sh all
```

You'll see prompts like:
- `[S] Skip` - Skip this step (recommended if resource is healthy)
- `[P] Proceed` - Run deployment anyway (may update existing resource)
- `[V] View` - Show resource details
- `[A] Auto` - Auto-skip all remaining healthy resources
- `[Q] Quit` - Exit deployment

### Non-Interactive Mode

For CI/CD pipelines or automated deployments:

```bash
# Skip all existing resources automatically
INTERACTIVE_MODE=false SKIP_ALL=true ./deploy.sh all

# Proceed with all deployments (update existing)
INTERACTIVE_MODE=false ./deploy.sh all
```

---

## Configuration Files

### Helm Values

Located in `/helm-values/`:

| File | Purpose |
|------|---------|
| `litellm-values.yaml` | LiteLLM proxy (JWT, models, telemetry) |
| `openwebui-values.yaml` | OpenWebUI frontend (Okta OIDC) |
| `redis-values.yaml` | Redis HA cluster |
| `kube-prometheus-stack-values.yaml` | Prometheus/Grafana/Alertmanager |
| `jaeger-values.yaml` | Distributed tracing |
| `external-secrets-values.yaml` | External Secrets Operator |
| `gatekeeper-values.yaml` | OPA Gatekeeper policy engine |

### Kubernetes Manifests

Located in `/manifests/`:

| File | Purpose |
|------|---------|
| `namespaces.yaml` | Namespace definitions |
| `cluster-secret-store.yaml` | AWS Secrets Manager integration |
| `litellm-external-secret.yaml` | LiteLLM secrets sync |
| `openwebui-external-secret.yaml` | OpenWebUI secrets sync |
| `opa-policies/` | OPA Gatekeeper policies |

### IAM Policies

Located in `/iam/`:

| File | Purpose |
|------|---------|
| `litellm-bedrock-policy.json` | Bedrock model access permissions |
| `external-secrets-policy.json` | Secrets Manager read permissions |
| `trust-policy-template.json` | IRSA trust policy template |

---

## JWT Authentication Flow

### How It Works

1. **User authenticates with Okta**
   - User visits OpenWebUI
   - Redirected to Okta login page
   - Enters credentials
   - Okta issues JWT token with claims (email, groups, etc.)

2. **OpenWebUI stores session**
   - Receives JWT from Okta callback
   - Validates token
   - Creates encrypted session (using WEBUI_SECRET_KEY)
   - User is now logged in

3. **User sends chat request**
   - OpenWebUI extracts user's JWT token
   - Sends request to LiteLLM with `Authorization: Bearer <jwt-token>`
   - Request includes user context

4. **LiteLLM validates JWT**
   - Fetches Okta public keys from `jwt_public_key_url`
   - Validates token signature
   - Extracts user claims (email, groups, sub)
   - Checks permissions (optional)
   - Logs request with user context

5. **LiteLLM routes to Bedrock**
   - Uses IRSA credentials (no static keys)
   - Calls Claude/Llama models
   - Streams response back to user

### Key Configuration

**LiteLLM (`litellm-values.yaml`):**
```yaml
general_settings:
  enable_jwt_auth: true
  jwt_public_key_url: "os.environ/JWT_PUBLIC_KEY_URL"
```

**OpenWebUI (`openwebui-values.yaml`):**
```yaml
extraEnvVars:
  - name: OAUTH_PROVIDER
    value: "oidc"
  - name: OPENID_PROVIDER_URL
    valueFrom:
      secretKeyRef:
        name: openwebui-secrets
        key: okta-openid-url
```

**See [JWT_AUTHENTICATION_SETUP.md](JWT_AUTHENTICATION_SETUP.md)** for complete Okta configuration.

---

## Required AWS Secrets Summary

### LiteLLM Namespace

| Secret Name | Description | How Created |
|------------|-------------|-------------|
| `litellm/master-key` | LiteLLM API master key | Auto-generated by deploy script |
| `litellm/salt-key` | Database encryption salt (CANNOT change) | Auto-generated by deploy script |
| `litellm/redis-password` | Redis authentication password | Auto-generated by deploy script |
| `litellm/database-url` | PostgreSQL connection string | **Manual** (from Terraform outputs) |
| `litellm/jwt-public-key-url` | Okta JWKS endpoint | **Manual** (Okta domain) |

### OpenWebUI Namespace

| Secret Name | Description | How Created |
|------------|-------------|-------------|
| `openwebui/webui-secret-key` | Session encryption key | **Manual** |
| `openwebui/okta-openid-url` | Okta OpenID discovery URL | **Manual** |
| `openwebui/okta-client-id` | Okta application client ID | **Manual** |
| `openwebui/okta-client-secret` | Okta application client secret | **Manual** |
| `openwebui/admin-email` | Admin user emails (comma-separated) | **Manual** |

---

## Troubleshooting

### ExternalSecrets Not Syncing

**Symptoms:**
```bash
kubectl get externalsecret -n litellm
NAME              STORE                  STATUS   AGE
litellm-secrets   aws-secrets-manager    Failed   2m
```

**Diagnosis:**
```bash
kubectl describe externalsecret litellm-secrets -n litellm
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

**Common Causes:**
1. IAM role for External Secrets Operator not configured
2. Secret doesn't exist in AWS Secrets Manager
3. Incorrect region in ClusterSecretStore

**Solution:**
```bash
# Verify IAM role exists
aws iam get-role --role-name external-secrets-role

# Verify secrets exist
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `litellm/`) || starts_with(Name, `openwebui/`)].Name'

# Check External Secrets Operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### LiteLLM JWT Validation Fails

**Symptoms:**
```bash
curl -H "Authorization: Bearer <jwt-token>" http://litellm:4000/v1/chat/completions
# Returns: 401 Unauthorized
```

**Diagnosis:**
```bash
kubectl logs -n litellm -l app.kubernetes.io/name=litellm | grep -i jwt
```

**Common Causes:**
1. `JWT_PUBLIC_KEY_URL` incorrect or unreachable
2. Token expired
3. Token signature invalid
4. Wrong Okta domain

**Solution:**
```bash
# Verify JWT_PUBLIC_KEY_URL
kubectl get secret litellm-secrets -n litellm -o jsonpath='{.data.jwt-public-key-url}' | base64 -d
# Should output: https://<your-okta-domain>/oauth2/default/v1/keys

# Test URL manually
curl https://<your-okta-domain>/oauth2/default/v1/keys

# Decode JWT token to inspect claims
# Visit https://jwt.io and paste your token
```

### OpenWebUI OAuth Login Fails

**Symptoms:**
- Clicking "Sign in with Okta" returns error
- Redirects to error page

**Diagnosis:**
```bash
kubectl logs -n open-webui -l app.kubernetes.io/name=open-webui | tail -50
```

**Common Causes:**
1. Incorrect Okta client ID/secret
2. Callback URL mismatch
3. Missing scopes

**Solution:**
1. Verify secrets in AWS Secrets Manager
2. Check Okta app redirect URIs match OpenWebUI URL
3. Ensure scopes include: `openid email profile groups`

### Pods Stuck in Pending

**Symptoms:**
```bash
kubectl get pods -n litellm
NAME                      READY   STATUS    RESTARTS   AGE
litellm-xxx               0/1     Pending   0          5m
```

**Diagnosis:**
```bash
kubectl describe pod litellm-xxx -n litellm
```

**Common Causes:**
1. Insufficient cluster resources
2. PVC not bound (for Redis/OpenWebUI)
3. Node selector not matching

**Solution:**
```bash
# Check cluster capacity
kubectl top nodes

# Check PVC status
kubectl get pvc -A

# Check node labels
kubectl get nodes --show-labels
```

**For comprehensive troubleshooting, see [OPERATIONS.md](OPERATIONS.md).**

---

## Manual Deployment (Without Script)

If you prefer to deploy manually without using the deploy script:

### 1. Set Environment Variables

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export EKS_CLUSTER_NAME=my-eks-cluster
export OIDC_PROVIDER=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION \
    --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
```

### 2. Create IAM Roles (IRSA)

```bash
# Create LiteLLM Bedrock role
cat > /tmp/litellm-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:litellm:litellm-sa"
      }
    }
  }]
}
EOF

aws iam create-role --role-name litellm-bedrock-role \
    --assume-role-policy-document file:///tmp/litellm-trust-policy.json
aws iam put-role-policy --role-name litellm-bedrock-role \
    --policy-name bedrock-invoke --policy-document file://iam/litellm-bedrock-policy.json

# Create External Secrets role
cat > /tmp/eso-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:external-secrets:external-secrets"
      }
    }
  }]
}
EOF

aws iam create-role --role-name external-secrets-role \
    --assume-role-policy-document file:///tmp/eso-trust-policy.json
aws iam put-role-policy --role-name external-secrets-role \
    --policy-name secrets-manager-read --policy-document file://iam/external-secrets-policy.json
```

### 3. Update Configuration Files

```bash
sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" helm-values/litellm-values.yaml
sed -i "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" helm-values/external-secrets-values.yaml
sed -i "s/us-east-1/$AWS_REGION/g" manifests/cluster-secret-store.yaml
```

### 4. Add Helm Repositories

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo add dandydev https://dandydeveloper.github.io/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-webui https://helm.openwebui.com/
helm repo update
```

### 5. Deploy Components

```bash
# Create namespaces
kubectl apply -f manifests/namespaces.yaml

# Deploy External Secrets Operator
helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets -f helm-values/external-secrets-values.yaml --wait

# Wait for webhook to be ready
kubectl rollout status deployment/external-secrets-webhook -n external-secrets --timeout=120s

# Create secret stores and wait for them to be ready
kubectl apply -f manifests/cluster-secret-store.yaml
kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=60s

# Create ExternalSecrets
kubectl apply -f manifests/litellm-external-secret.yaml
kubectl apply -f manifests/openwebui-external-secret.yaml

# Wait for secrets to sync
kubectl wait --for=condition=Ready externalsecret/litellm-secrets -n litellm --timeout=60s
kubectl wait --for=condition=Ready externalsecret/openwebui-secrets -n open-webui --timeout=60s

# Deploy monitoring stack
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring -f helm-values/kube-prometheus-stack-values.yaml --wait

# Deploy Redis HA
helm upgrade --install redis dandydev/redis-ha \
    -n litellm -f helm-values/redis-values.yaml --wait

# Deploy LiteLLM
helm pull oci://ghcr.io/berriai/litellm-helm --untar -d /tmp/
helm upgrade --install litellm /tmp/litellm-helm \
    -n litellm -f helm-values/litellm-values.yaml --wait

# Deploy OpenWebUI
helm upgrade --install open-webui open-webui/open-webui \
    -n open-webui -f helm-values/openwebui-values.yaml --wait
```

---

## Security Considerations

### 1. Secret Rotation

Rotate secrets regularly:

```bash
# Rotate Redis password
NEW_PASSWORD=$(openssl rand -hex 16)
aws secretsmanager update-secret \
  --secret-id litellm/redis-password \
  --secret-string "$NEW_PASSWORD"

# Restart Redis and LiteLLM pods
kubectl rollout restart statefulset/redis-redis-ha-server -n litellm
kubectl rollout restart deployment/litellm -n litellm
```

### 2. JWT Token Lifetime

Configure short-lived tokens in Okta (15-60 minutes recommended).

### 3. HTTPS Only

In production, configure ingress with TLS:
- Use AWS Application Load Balancer with ACM certificate
- Or use nginx-ingress with cert-manager

### 4. Network Policies

Consider adding Kubernetes NetworkPolicies to restrict pod-to-pod communication.

### 5. OPA Policies

Review and enforce OPA Gatekeeper policies:

```bash
# View current policies
kubectl get constrainttemplates
kubectl get constraints

# Change from dryrun to enforce
# Edit constraint and set: enforcementAction: deny
```

---

## Additional Resources

### Documentation
- [Main README](../README.md) - Quick start and overview
- [JWT Authentication Setup Guide](./JWT_AUTHENTICATION_SETUP.md) - Detailed Okta configuration
- [MCP Deployment Guide](./MCP_DEPLOYMENT.md) - Deploy Model Context Protocol servers
- [Operations Guide](./OPERATIONS.md) - Monitoring, troubleshooting, maintenance
- [OPA Policies README](../manifests/opa-policies/README.md) - Security policy details
- [Scripts README](../scripts/README.md) - Deployment script documentation

### External Resources
- [LiteLLM Documentation](https://docs.litellm.ai/) - LiteLLM proxy features and configuration
- [OpenWebUI Documentation](https://docs.openwebui.com/) - OpenWebUI setup and customization
- [AWS Bedrock Models](https://aws.amazon.com/bedrock/claude/) - Available models and pricing
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/) - Policy enforcement
- [External Secrets Operator](https://external-secrets.io/) - Secret management
